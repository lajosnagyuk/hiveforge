defmodule HiveforgeController.Services.HashProcessingService do
  alias HiveforgeController.Repo
  alias HiveforgeController.Schemas.{HashResult, FileEntry, Chunk, FileChunk, DirectoryEntry}
  alias HiveforgeController.Storage.StorageService
  require Logger
  import Ecto.Query

  @batch_size 1000

  def process_hash_result(params) do
    Repo.transaction(fn ->
      with {:ok, hash_result} <- create_hash_result(params),
           {:ok, entries} <- process_directory(hash_result.id, params),
           {:ok, stored_directory_entries} <- store_directory_entries(Enum.filter(entries, &Map.has_key?(&1, :name))),
           {:ok, stored_file_entries} <- store_file_entries(Enum.reject(entries, &Map.has_key?(&1, :name))),
           :ok <- store_chunks(stored_file_entries),
           :ok <- store_file_chunks(stored_file_entries) do
        hash_result  # Return the hash_result directly, not wrapped in {:ok, _}
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          Logger.error("Validation error: #{inspect(changeset.errors)}", error_type: :validation_error)
          Repo.rollback({:validation_error, changeset})
        {:error, :directory_entry_insertion_failed} ->
          Logger.error("Failed to insert directory entries", error_type: :database_error)
          Repo.rollback(:directory_entry_insertion_failed)
        {:error, :file_entry_insertion_failed} ->
          Logger.error("Failed to insert file entries", error_type: :database_error)
          Repo.rollback(:file_entry_insertion_failed)
        {:error, :chunk_insertion_failed} ->
          Logger.error("Failed to insert chunks", error_type: :database_error)
          Repo.rollback(:chunk_insertion_failed)
        {:error, :file_chunks_insertion_failed} ->
          Logger.error("Failed to insert file chunks", error_type: :database_error)
          Repo.rollback(:file_chunks_insertion_failed)
        {:error, reason} ->
          Logger.error("Unexpected error: #{inspect(reason)}", error_type: :unexpected_error)
          Repo.rollback(reason)
      end
    end)
  end

  defp create_hash_result(params) do
    %HashResult{}
    |> HashResult.changeset(%{
      root_path: params["root"],
      total_files: params["files"],
      total_size: params["size"],
      hashing_time: params["time"],
      status: "completed",
      s3_key: StorageService.generate_s3_key(params["root"]),
      s3_backend: System.get_env("S3_BACKEND")
    })
    |> Repo.insert()
  end

  defp process_directory(hash_result_id, params) do
    Logger.debug("Processing root directory: #{inspect(params["root"])}")
    process_entries(hash_result_id, params["dir"], params["root"])
  end

  defp process_entries(hash_result_id, entries, current_path, acc \\ [])

  defp process_entries(hash_result_id, entries, current_path, acc) when is_list(entries) do
    Logger.debug("Processing #{length(entries)} entries in #{current_path}")
    Enum.reduce_while(entries, {:ok, acc}, fn entry, {:ok, acc} ->
      case process_entry(hash_result_id, entry, current_path) do
        {:ok, new_entries} -> {:cont, {:ok, new_entries ++ acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp process_entries(hash_result_id, %{"name" => name, "type" => "directory", "children" => children}, current_path, acc) do
    Logger.debug("Processing directory: #{name} in #{current_path}")
    process_entries(hash_result_id, children, Path.join(current_path, name), acc)
  end

  defp process_entries(_, entry, _, _) do
    Logger.warn("Unexpected entry structure: #{inspect(entry)}")
    {:error, :invalid_entry_structure}
  end

  defp process_entry(hash_result_id, entry, current_path) do
    Logger.debug("Processing entry: #{inspect(entry)}")
    case entry do
      %{"name" => name, "type" => "file", "size" => size, "hashes" => hashes} ->
        path = Path.join(current_path, name)
        file_entry = %{
          hash_result_id: hash_result_id,
          path: path,
          file_name: name,
          size: size,
          chunk_size: hashes["chunkSize"],
          chunk_count: hashes["chunkCount"],
          chunks: hashes["hashes"]
        }
        {:ok, [file_entry]}

      %{"name" => name, "type" => "directory", "children" => children} ->
        path = Path.join(current_path, name)
        directory_entry = %{
          hash_result_id: hash_result_id,
          path: path,
          name: name
        }
        case process_entries(hash_result_id, children, path) do
          {:ok, new_entries} -> {:ok, [directory_entry | new_entries]}
          {:error, reason} -> {:error, reason}
        end

      %{"name" => name, "type" => "directory", "size" => 0} ->
        path = Path.join(current_path, name)
        directory_entry = %{
          hash_result_id: hash_result_id,
          path: path,
          name: name
        }
        {:ok, [directory_entry]}

      _ ->
        Logger.warn("Skipping unexpected entry: #{inspect(entry)}")
        {:ok, []}
    end
  end

  defp store_directory_entries(directory_entries) do
    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries_with_timestamps = Enum.map(directory_entries, fn entry ->
      Map.merge(entry, %{inserted_at: timestamp, updated_at: timestamp})
    end)

    Repo.transaction(fn ->
      Enum.chunk_every(entries_with_timestamps, @batch_size)
      |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
        case Repo.insert_all(DirectoryEntry, batch, returning: [:id, :path]) do
          {count, stored_entries} ->
            Logger.info("Inserted #{count} directory entries")
            {:cont, {:ok, acc ++ stored_entries}}
          _ ->
            {:halt, {:error, :directory_entry_insertion_failed}}
        end
      end)
    end)
    |> case do
      {:ok, {:ok, stored_entries}} ->
        stored_entries_map = Map.new(stored_entries, fn entry -> {entry.path, entry} end)
        updated_directory_entries = Enum.map(directory_entries, fn entry ->
          stored_entry = Map.get(stored_entries_map, entry.path)
          Map.put(entry, :id, stored_entry.id)
        end)
        {:ok, updated_directory_entries}
      {:error, _} = error -> error
    end
  end

  defp store_file_entries(file_entries) do
    entries_without_chunks = Enum.map(file_entries, &Map.drop(&1, [:chunks]))
    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries_with_timestamps = Enum.map(entries_without_chunks, fn entry ->
      Map.merge(entry, %{inserted_at: timestamp, updated_at: timestamp})
    end)

    Repo.transaction(fn ->
      Enum.chunk_every(entries_with_timestamps, @batch_size)
      |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
        case Repo.insert_all(FileEntry, batch, returning: [:id, :path]) do
          {count, stored_entries} ->
            Logger.info("Inserted #{count} file entries")
            {:cont, {:ok, acc ++ stored_entries}}
          _ ->
            {:halt, {:error, :file_entry_insertion_failed}}
        end
      end)
    end)
    |> case do
      {:ok, {:ok, stored_entries}} ->
        stored_entries_map = Map.new(stored_entries, fn entry -> {entry.path, entry} end)
        updated_file_entries = Enum.map(file_entries, fn entry ->
          stored_entry = Map.get(stored_entries_map, entry.path)
          Map.put(entry, :id, stored_entry.id)
        end)
        {:ok, updated_file_entries}
      {:error, _} = error -> error
    end
  end

  defp store_chunks(file_entries) do
    chunks = file_entries
    |> Enum.flat_map(& &1.chunks)
    |> Enum.uniq()
    |> Enum.map(&%{hash: &1, status: "pending", size: 0})

    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    chunks_with_timestamps = Enum.map(chunks, fn chunk ->
      Map.merge(chunk, %{inserted_at: timestamp, updated_at: timestamp})
    end)

    Enum.chunk_every(chunks_with_timestamps, @batch_size)
    |> Enum.each(fn batch ->
      {count, _} = Repo.insert_all(Chunk, batch, on_conflict: :nothing)
      Logger.info("Inserted #{count} chunks")
    end)

    :ok
  end

  defp store_file_chunks(file_entries) do
    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # First, fetch all chunk IDs
    chunk_hashes = file_entries |> Enum.flat_map(&(&1.chunks)) |> Enum.uniq()
    chunk_id_map = fetch_chunk_ids(chunk_hashes)

    file_chunks = for file_entry <- file_entries,
                      {chunk_hash, index} <- Enum.with_index(file_entry.chunks),
                      chunk_id = Map.get(chunk_id_map, chunk_hash) do
      %{
        file_entry_id: file_entry.id,
        chunk_id: chunk_id,
        sequence: index,
        inserted_at: timestamp,
        updated_at: timestamp
      }
    end

    Enum.chunk_every(file_chunks, @batch_size)
    |> Enum.reduce_while(:ok, fn batch, _ ->
      case Repo.insert_all(FileChunk, batch) do
        {count, _} when count > 0 ->
          Logger.info("Inserted #{count} file chunks")
          {:cont, :ok}
        {0, _} ->
          Logger.error("Failed to insert file chunks batch")
          {:halt, {:error, :file_chunks_insertion_failed}}
      end
    end)
  end

  defp fetch_chunk_ids(chunk_hashes) do
    Chunk
    |> where([c], c.hash in ^chunk_hashes)
    |> select([c], {c.hash, c.id})
    |> Repo.all()
    |> Map.new()
  end
end
