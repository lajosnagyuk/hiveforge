
defmodule HiveforgeController.HashService do
  alias HiveforgeController.Repo
  alias HiveforgeController.Schemas.{HashResult, FileHash, ChunkHash, FileChunkMap}
  import Ecto.Query

  def process_hash_result(json_data) do
    Repo.transaction(fn ->
      with {:ok, hash_result} <- create_hash_result(json_data),
           :ok <- process_files(hash_result, json_data["dir"]["children"]) do
        hash_result  # Return just the hash_result, not {:ok, hash_result}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp create_hash_result(json_data) do
    attrs = %{
      root_path: json_data["root"],
      total_files: json_data["files"],
      total_size: json_data["size"],
      hashing_time: json_data["time"],
      status: "completed"
    }

    %HashResult{}
    |> HashResult.changeset(attrs)
    |> Repo.insert()
  end

  defp process_files(hash_result, files) when is_list(files) do
    Enum.each(files, fn file ->
      process_file(hash_result, file)
    end)
    :ok
  end

  defp process_files(hash_result, %{"children" => children}) do
    process_files(hash_result, children)
  end

  def get_ordered_chunks(file_hash_id) do
    Repo.all(from fcm in FileChunkMap,
      join: ch in ChunkHash, on: fcm.chunk_hash_id == ch.id,
      where: fcm.file_hash_id == ^file_hash_id,
      order_by: [asc: fcm.sequence],
      select: %{sequence: fcm.sequence, hash: ch.hash, status: ch.status}
    )
  end

  defp process_file(hash_result, %{"type" => "file"} = file) do
    attrs = %{
      file_name: file["name"],
      chunk_size: file["hashes"]["chunkSize"],
      chunk_count: file["hashes"]["chunkCount"],
      total_size: file["size"],
      status: "completed",
      hash_result_id: hash_result.id
    }

    {:ok, file_hash} =
      %FileHash{}
      |> FileHash.changeset(attrs)
      |> Repo.insert()

    process_chunks(file_hash, file["hashes"]["hashes"])
  end

  defp process_file(hash_result, %{"type" => "directory", "children" => children}) do
    process_files(hash_result, children)
  end

  defp process_file(hash_result, unexpected) do
    Logger.error("Unexpected structure in process_file: #{inspect(unexpected)}")
    {:error, :unexpected_structure}
  end

  defp process_chunks(file_hash, chunks) do
    chunks
    |> Enum.with_index(1)  # Start index at 1
    |> Enum.each(fn {chunk, index} ->
      process_chunk(file_hash, chunk, index)
    end)
  end

  defp update_file_hash(chunk_hashes, file_hash) do
    chunk_ids = Enum.map(chunk_hashes, & &1.id)
    FileHash.changeset(file_hash, %{chunk_hashes: chunk_ids})
    |> Repo.update()
  end

  defp process_chunk(file_hash, chunk, sequence) do
    chunk_hash = get_or_create_chunk_hash(chunk)
    create_file_chunk_map(file_hash, chunk_hash, sequence)
  end

  defp get_or_create_chunk_hash(chunk) do
    case Repo.one(from ch in ChunkHash, where: ch.hash == ^chunk, limit: 1) do
      nil ->
        {:ok, chunk_hash} =
          %ChunkHash{}
          |> ChunkHash.changeset(%{hash: chunk, status: "missing"})
          |> Repo.insert()
        chunk_hash

      existing_chunk ->
        existing_chunk
    end
  end

  defp create_file_chunk_map(file_hash, chunk_hash, sequence) do
    %FileChunkMap{}
    |> FileChunkMap.changeset(%{
      file_hash_id: file_hash.id,
      chunk_hash_id: chunk_hash.id,
      sequence: sequence
    })
    |> Repo.insert()
  end

  def find_missing_chunks(root_path) do
    query =
      from fcm in FileChunkMap,
      join: ch in ChunkHash, on: fcm.chunk_hash_id == ch.id,
      join: fh in FileHash, on: fcm.file_hash_id == fh.id,
      join: hr in HashResult, on: fh.hash_result_id == hr.id,
      where: hr.root_path == ^root_path and ch.status == "missing",
      select: {hr.id, fh.id, fh.file_name, ch.hash, fcm.sequence}
    Repo.all(query)
  end

  def update_chunk_status(chunk_hash_id, new_status) do
    ChunkHash
    |> Repo.get(chunk_hash_id)
    |> ChunkHash.changeset(%{status: new_status})
    |> Repo.update()
  end

  def get_hash_result_by_root_path(root_path) do
    Repo.get_by(HashResult, root_path: root_path)
  end

  def get_file_hashes_by_hash_result(hash_result_id) do
    FileHash
    |> where(hash_result_id: ^hash_result_id)
    |> Repo.all()
  end

  def get_chunk_hashes_by_file_hash(file_hash_id) do
    Repo.all(from fcm in FileChunkMap,
      join: ch in ChunkHash, on: fcm.chunk_hash_id == ch.id,
      where: fcm.file_hash_id == ^file_hash_id,
      order_by: [asc: fcm.sequence],
      select: %{sequence: fcm.sequence, hash: ch.hash, status: ch.status}
    )
  end

  def delete_hash_result(hash_result_id) do
    HashResult
    |> Repo.get(hash_result_id)
    |> Repo.delete()
  end

  def update_hash_result_status(hash_result_id, new_status) do
    HashResult
    |> Repo.get(hash_result_id)
    |> HashResult.changeset(%{status: new_status})
    |> Repo.update()
  end
end
