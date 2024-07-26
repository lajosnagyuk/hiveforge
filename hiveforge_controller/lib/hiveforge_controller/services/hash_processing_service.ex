defmodule HiveforgeController.Services.HashProcessingService do
  use Plug.Builder
  alias HiveforgeController.Repo
  alias HiveforgeController.Schemas.{HashResult, DirectoryEntry, FileResult, Chunk, FileChunk}
  alias HiveforgeController.Storage.StorageService
  alias HiveforgeController.SetConfig
  require Logger
  import Ecto.Query
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    super(conn, opts)
  end

  defp fetch_body(conn, _opts) do
    {:ok, body, conn} = read_body(conn)
    assign(conn, :raw_body, body)
  end

  def process_hash_result(params) do
    Repo.transaction(fn ->
      with {:ok, hash_result} <- create_hash_result(params),
           {:ok, _} <- process_directory_structure(hash_result, params["dir"]) do
        hash_result
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          Logger.error("Validation error: #{inspect(changeset.errors)}")
          Repo.rollback({:validation_error, changeset})
        {:error, reason} ->
          Logger.error("Unexpected error: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
  end

  defp create_hash_result(params) do
    %HashResult{}
    |> HashResult.changeset(%{
      root_path: params["root"],
      total_size: params["size"],
      total_files: params["files"],
      hashing_time: params["time"],
      status: "completed", # Add this line
      s3_key: StorageService.generate_s3_key(params["root"]),
      s3_backend: SetConfig.get(:s3_backend)
    })
    |> Repo.insert()
  end

  defp process_directory_structure(hash_result, dir_entry, parent_path \\ nil, parent_id \\ nil) do
    current_path = build_path(parent_path, dir_entry["name"])

    attrs = %{
      name: dir_entry["name"],
      type: dir_entry["type"],
      size: dir_entry["size"],
      path: current_path,
      hash_result_id: hash_result.id,
      parent_id: parent_id
    }

    with {:ok, directory_entry} <- create_directory_entry(attrs),
         :ok <- maybe_create_file_result(directory_entry, dir_entry["file_result"]),
         :ok <- process_children(hash_result, directory_entry, current_path, dir_entry["children"]) do
      {:ok, directory_entry}
    end
  end

  defp build_path(nil, name), do: name
  defp build_path(parent_path, name), do: Path.join(parent_path, name)

  defp process_children(_hash_result, _parent_entry, _parent_path, nil), do: :ok
  defp process_children(hash_result, parent_entry, parent_path, children) when is_list(children) do
    Enum.each(children, fn child ->
      process_directory_structure(hash_result, child, parent_path, parent_entry.id)
    end)
    :ok
  end

  defp create_directory_entry(attrs) do
    %DirectoryEntry{}
    |> DirectoryEntry.changeset(attrs)
    |> Repo.insert()
  end

  defp maybe_create_file_result(directory_entry, nil), do: :ok
  defp maybe_create_file_result(directory_entry, file_result) do
    attrs = %{
      name: file_result["file_info"]["name"],
      size: file_result["file_info"]["size"],
      hash: file_result["file_info"]["hash"],
      algorithm: file_result["chunking_info"]["algorithm"],
      average_chunk_size: file_result["chunking_info"]["average_chunk_size"],
      min_chunk_size: file_result["chunking_info"]["min_chunk_size"],
      max_chunk_size: file_result["chunking_info"]["max_chunk_size"],
      total_chunks: file_result["chunking_info"]["total_chunks"],
      directory_entry_id: directory_entry.id
    }

    with {:ok, file_result_record} <- create_file_result(attrs),
         :ok <- create_chunks_and_associations(file_result_record, file_result["chunks"]) do
      :ok
    end
  end

  defp create_file_result(attrs) do
    %FileResult{}
    |> FileResult.changeset(attrs)
    |> Repo.insert()
  end

  defp create_chunks_and_associations(file_result_record, chunks) do
    Enum.with_index(chunks, fn chunk, index ->
      with {:ok, chunk_record} <- create_or_get_chunk(chunk),
           {:ok, _} <- create_file_chunk_association(file_result_record, chunk_record, index, chunk["offset"]) do
        :ok
      else
        {:error, reason} -> {:error, reason}
      end
    end)
    |> Enum.all?(&(&1 == :ok))
    |> case do
      true -> :ok
      false -> {:error, :chunk_creation_failed}
    end
  end

  defp create_or_get_chunk(chunk) do
    case Repo.get_by(Chunk, hash: chunk["hash"]) do
      nil ->
        %Chunk{}
        |> Chunk.changeset(%{hash: chunk["hash"], size: chunk["size"]})
        |> Repo.insert()
      existing_chunk ->
        {:ok, existing_chunk}
    end
  end

  defp create_file_chunk_association(file_result, chunk, sequence, offset) do
    %FileChunk{}
    |> FileChunk.changeset(%{
      file_result_id: file_result.id,
      chunk_id: chunk.id,
      sequence: sequence,
      offset: offset
    })
    |> Repo.insert()
  end

  defp process_children(_hash_result, _parent_entry, nil), do: :ok
  defp process_children(hash_result, parent_entry, children) when is_list(children) do
    Enum.each(children, fn child ->
      process_directory_structure(hash_result, child, parent_entry.id)
    end)
    :ok
  end
end
