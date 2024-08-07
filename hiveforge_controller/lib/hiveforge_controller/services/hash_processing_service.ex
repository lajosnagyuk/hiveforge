defmodule HiveforgeController.Services.HashProcessingService do
  alias HiveforgeController.Repo
  alias HiveforgeController.Schemas.{HashResult, DirectoryEntry, FileResult, Chunk, FileChunk}
  alias HiveforgeController.Storage.StorageService
  alias HiveforgeController.Services.{RobustStringSanitizer, UIDGenerator}
  alias HiveforgeController.SetConfig
  import Ecto.Query
  require Logger

  @chunk_batch_size 10000
  @file_batch_size 1000

  def process_hash_result(params) do
    Repo.transaction(fn ->
      with {:ok, hash_result} <- create_hash_result(params),
           {:ok, directory_entries} <- process_directory_entries(hash_result, params["dir"]),
           {:ok, file_results} <- process_file_results(hash_result, params["dir"]),
           {:ok, chunks} <- process_chunks(hash_result, params["dir"]),
           {:ok, file_chunks} <- process_file_chunks(hash_result, params["dir"]) do
        Logger.info("Successfully processed hash result for #{hash_result.root_path}. " <>
                    "Inserted: #{length(List.wrap(directory_entries))} directory entries, " <>
                    "#{length(List.wrap(file_results))} file results, " <>
                    "#{length(List.wrap(chunks))} chunks, " <>
                    "#{file_chunks} file chunks.")
        hash_result
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          Logger.error("Validation error in process_hash_result: #{inspect(changeset.errors)}")
          Repo.rollback({:validation_error, changeset})
        {:error, step, reason} ->
          Logger.error("Error in process_hash_result at step #{step}: #{inspect(reason)}")
          Repo.rollback({:process_error, step, reason})
        {:error, reason} ->
          Logger.error("Unexpected error in process_hash_result: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
  end

  defp create_hash_result(params) do
    uid = UIDGenerator.generate()
    %HashResult{}
    |> HashResult.changeset(%{
      uid: uid,
      root_path: params["root"],
      total_size: params["size"],
      total_files: params["files"],
      hashing_time: params["time"],
      status: "processing",
      s3_key: StorageService.generate_s3_key(params["root"]),
      s3_backend: SetConfig.get(:s3_backend)
    })
    |> Repo.insert()
  end


  defp prepare_file_result(file_entry, hash_result_uid, parent_directory_path, file_path) do
    file_result = file_entry["file_result"]
    %{
      uid: UIDGenerator.generate(),
      name: RobustStringSanitizer.sanitize(file_result["file_info"]["name"]),
      size: file_result["file_info"]["size"],
      hash: RobustStringSanitizer.sanitize(file_result["file_info"]["hash"]),
      algorithm: file_result["chunking_info"]["algorithm"],
      average_chunk_size: file_result["chunking_info"]["average_chunk_size"],
      min_chunk_size: file_result["chunking_info"]["min_chunk_size"],
      max_chunk_size: file_result["chunking_info"]["max_chunk_size"],
      total_chunks: file_result["chunking_info"]["total_chunks"],
      path: RobustStringSanitizer.sanitize(file_path),
      parent_directory_path: RobustStringSanitizer.sanitize(parent_directory_path),
      hash_result_uid: hash_result_uid,
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
  end

  defp extract_file_chunks_with_paths(dir_entry, hash_result_uid, current_path \\ "") do
    new_path = Path.join(current_path, sanitize_string(dir_entry["name"]))

    if dir_entry["type"] == "file" do
      file_result = dir_entry["file_result"]
      Enum.map(file_result["chunks"], fn chunk ->
        %{
          sequence: chunk["sequence"] || 0,
          offset: chunk["offset"],
          file_path: new_path,
          hash_result_uid: hash_result_uid,
          chunk_hash: sanitize_string(chunk["hash"])
        }
      end)
    else
      Enum.flat_map(dir_entry["children"] || [], &extract_file_chunks_with_paths(&1, hash_result_uid, new_path))
    end
  end

  defp process_directory_entries(hash_result, dir_entry) do
    entries = flatten_directory_structure(dir_entry, hash_result.uid)
    case insert_directory_entries_hierarchically(entries) do
      {:ok, inserted_map} ->
        {:ok, Map.values(inserted_map)}
      error -> error
    end
  end

  defp insert_directory_entries_hierarchically(entries) do
    entries
    |> Enum.group_by(& &1.parent_path)
    |> Enum.sort_by(fn {parent_path, _} -> String.length(parent_path || "") end)
    |> Enum.reduce_while({:ok, %{}}, fn {parent_path, group}, {:ok, inserted_map} ->
      parent_uid = Map.get(inserted_map, parent_path)

      entries_to_insert = Enum.map(group, fn entry ->
        Map.put(entry, :parent_uid, parent_uid)
      end)

      case Repo.insert_all(DirectoryEntry, entries_to_insert, on_conflict: :nothing, returning: [:uid, :path]) do
        {_, inserted} ->
          new_inserted_map = Enum.reduce(inserted, inserted_map, fn entry, acc ->
            Map.put(acc, entry.path, entry.uid)
          end)
          {:cont, {:ok, new_inserted_map}}
        error ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp process_file_results(hash_result, dir_entry) do
    file_entries = extract_file_entries(dir_entry)
    Logger.debug("Processing #{length(file_entries)} file entries")

    result = file_entries
    |> Stream.map(fn file_entry ->
      parent_dir_path = file_entry["parent_path"] || ""
      file_path = Path.join(parent_dir_path, file_entry["name"])
      prepare_file_result(file_entry, hash_result.uid, parent_dir_path, file_path)
    end)
    |> Stream.chunk_every(@file_batch_size)
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
      case Repo.insert_all(HiveforgeController.Schemas.FileResult, batch, on_conflict: :nothing, returning: [:uid]) do
        {inserted, results} ->
          {:cont, {:ok, acc ++ results}}
        error ->
          Logger.error("Error inserting file results batch: #{inspect(error)}")
          {:halt, {:error, error}}
      end
    end)

    case result do
      {:ok, inserted_results} -> {:ok, inserted_results}
      error -> error
    end
  end

  defp extract_file_entries(dir_entry, current_path \\ "") do
    new_path = Path.join(current_path, dir_entry["name"])
    Logger.debug("Extracting file entries from: #{inspect(dir_entry, pretty: true)}")

    result = if dir_entry["type"] == "file" do
      Logger.debug("Found file: #{new_path}")
      [Map.put(dir_entry, "parent_path", current_path)]
    else
      Logger.debug("Processing directory: #{new_path}")
      Enum.flat_map(dir_entry["children"] || [], &extract_file_entries(&1, new_path))
    end

    Logger.debug("Extracted #{length(result)} file entries from #{new_path}")
    result
  end

  defp safe_insert_all(schema, batch) do
    try do
      result = Repo.insert_all(schema, batch, on_conflict: :nothing)
      {:ok, result}
    rescue
      e in [Postgrex.Error, DBConnection.ConnectionError] ->
        Logger.error("Database error during insert_all: #{inspect(e)}")
        {:error, e}
    end
  end

  defp process_chunks(_hash_result, dir_entry) do
    chunks = extract_chunks(dir_entry)
    insert_all_in_batches(Repo, Chunk, chunks, @chunk_batch_size)
  end

  defp flatten_directory_structure(dir_entry, hash_result_uid, parent_path \\ nil) do
    uid = UIDGenerator.generate()
    current_path = Path.join([parent_path, sanitize_string(dir_entry["name"])] |> Enum.reject(&is_nil/1))

    entry = %{
      uid: uid,
      name: sanitize_string(dir_entry["name"]),
      type: dir_entry["type"],
      size: dir_entry["size"],
      path: sanitize_string(current_path),
      hash_result_uid: hash_result_uid,
      parent_path: sanitize_string(parent_path),
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }

    children_entries =
      if dir_entry["type"] == "directory" and dir_entry["children"] do
        Enum.flat_map(dir_entry["children"], &flatten_directory_structure(&1, hash_result_uid, current_path))
      else
        []
      end

    [entry | children_entries]
  end

  defp extract_chunks(dir_entry) do
    if dir_entry["type"] == "file" do
      Enum.map(dir_entry["file_result"]["chunks"], fn chunk ->
        %{
          uid: UIDGenerator.generate(),
          hash: sanitize_string(chunk["hash"]),
          size: chunk["size"],
          inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
          updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        }
      end)
    else
      Enum.flat_map(dir_entry["children"] || [], &extract_chunks/1)
    end
  end

  defp process_file_chunks(hash_result, dir_entry) do
    file_chunks = extract_file_chunks_with_paths(dir_entry, hash_result.uid)
    Logger.debug("Preparing to insert #{length(file_chunks)} file chunks")

    chunk_hashes = Enum.map(file_chunks, & &1.chunk_hash)
    file_paths = Enum.map(file_chunks, & &1.file_path)

    chunks_query = from c in Chunk, where: c.hash in ^chunk_hashes, select: {c.hash, c.uid}
    file_results_query = from fr in FileResult,
                          where: fr.path in ^file_paths and fr.hash_result_uid == ^hash_result.uid,
                          select: {fr.path, fr.uid}

    chunks = Repo.all(chunks_query)
    file_results = Repo.all(file_results_query)

    chunk_uid_map = Map.new(chunks, fn {hash, uid} -> {hash, uid} end)
    file_result_uid_map = Map.new(file_results, fn {path, uid} -> {path, uid} end)

    file_chunks_for_insert = Enum.map(file_chunks, fn chunk ->
      %{
        uid: UIDGenerator.generate(),
        sequence: chunk.sequence,
        offset: chunk.offset,
        file_path: RobustStringSanitizer.sanitize(chunk.file_path),
        file_result_uid: file_result_uid_map[chunk.file_path],
        chunk_uid: chunk_uid_map[chunk.chunk_hash],
        hash_result_uid: hash_result.uid,
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
        updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      }
    end)

    {valid_chunks, invalid_chunks} = Enum.split_with(file_chunks_for_insert, fn chunk ->
      chunk.chunk_uid != nil && chunk.file_result_uid != nil
    end)

    if length(invalid_chunks) > 0 do
      Logger.warning("#{length(invalid_chunks)} file chunks have missing associations")
      Logger.warning("Invalid chunks: #{inspect(invalid_chunks)}")
    end

    case Repo.insert_all(FileChunk, valid_chunks, on_conflict: :nothing) do
      {count, _} ->
        Logger.info("Successfully inserted #{count} file chunks")
        {:ok, count}
      error ->
        Logger.error("Failed to insert file chunks: #{inspect(error)}")
        {:error, error}
    end
  end

  defp sanitize_string(string) when is_binary(string) do
    case :unicode.characters_to_binary(string, :utf8, :utf8) do
      sanitized_string when is_binary(sanitized_string) ->
        sanitized_string
        |> String.replace(~r/[^\x20-\x7E]/, fn invalid_char ->
          Logger.warning("Sanitizing invalid character: #{inspect(invalid_char)}")
          "_"
        end)

      {:error, _reason} ->
        Logger.error("Invalid UTF-8 sequence found: #{inspect(string)}")
        "_"
    end
  rescue
    _ ->
      Logger.error("Error sanitizing string: #{inspect(string)}")
      "_"
  end

  defp sanitize_string(other), do: inspect(other)

  defp insert_all_in_batches(repo, schema, entries, batch_size) do
    entries
    |> Stream.chunk_every(batch_size)
    |> Enum.reduce_while({:ok, 0}, fn batch, {:ok, acc} ->
      Logger.debug("Inserting batch of #{length(batch)} entries for #{schema}")
      try do
        case repo.insert_all(schema, batch, on_conflict: :nothing) do
          {count, _} ->
            {:cont, {:ok, acc + count}}
          error ->
            Logger.error("Failed to insert batch for #{schema}: #{inspect(error)}")
            {:halt, {:error, error}}
        end
      rescue
        e ->
          Logger.error("Exception during batch insert for #{schema}: #{inspect(e)}")
          {:halt, {:error, e}}
      end
    end)
  end
end
