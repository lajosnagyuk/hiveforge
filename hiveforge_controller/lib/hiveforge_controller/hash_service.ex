# File: lib/hiveforge_controller/schemas/hash_result.ex
defmodule HiveforgeController.Schemas.HashResult do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hash_results" do
    field :root_path, :string
    field :total_files, :integer
    field :total_size, :integer
    field :hashing_time, :float
    field :status, :string, default: "pending"
    has_many :file_hashes, HiveforgeController.Schemas.FileHash
    timestamps()
  end

  def changeset(hash_result, attrs) do
    hash_result
    |> cast(attrs, [:root_path, :total_files, :total_size, :hashing_time, :status])
    |> validate_required([:root_path, :total_files, :total_size, :hashing_time])
  end
end

# File: lib/hiveforge_controller/schemas/file_hash.ex
defmodule HiveforgeController.Schemas.FileHash do
  use Ecto.Schema
  import Ecto.Changeset

  schema "file_hashes" do
    field :file_name, :string
    field :chunk_size, :integer
    field :chunk_count, :integer
    field :total_size, :integer
    field :status, :string, default: "pending"
    belongs_to :hash_result, HiveforgeController.Schemas.HashResult
    has_many :chunk_hashes, HiveforgeController.Schemas.ChunkHash
    timestamps()
  end

  def changeset(file_hash, attrs) do
    file_hash
    |> cast(attrs, [:file_name, :chunk_size, :chunk_count, :total_size, :status, :hash_result_id])
    |> validate_required([:file_name, :total_size, :hash_result_id])
  end
end

# File: lib/hiveforge_controller/schemas/chunk_hash.ex
defmodule HiveforgeController.Schemas.ChunkHash do
  use Ecto.Schema
  import Ecto.Changeset

  schema "chunk_hashes" do
    field :hash, :string
    field :status, :string, default: "pending"
    belongs_to :file_hash, HiveforgeController.Schemas.FileHash
    timestamps()
  end

  def changeset(chunk_hash, attrs) do
    chunk_hash
    |> cast(attrs, [:hash, :status, :file_hash_id])
    |> validate_required([:hash, :file_hash_id])
  end
end

# File: lib/hiveforge_controller/hash_service.ex
defmodule HiveforgeController.HashService do
  alias HiveforgeController.Repo
  alias HiveforgeController.Schemas.{HashResult, FileHash, ChunkHash}
  import Ecto.Query

  def process_hash_result(json_data) do
    Repo.transaction(fn ->
      with {:ok, hash_result} <- create_hash_result(json_data),
           :ok <- process_files(hash_result, json_data["dir"]["children"]) do
        {:ok, hash_result}
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

  defp process_files(hash_result, files) do
    Enum.each(files, fn file ->
      process_file(hash_result, file)
    end)
    :ok
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

  defp process_file(hash_result, %{"type" => "directory"} = dir) do
    process_files(hash_result, dir["children"])
  end

  defp process_chunks(file_hash, chunks) do
    Enum.each(chunks, fn chunk ->
      process_chunk(file_hash, chunk)
    end)
  end

  defp process_chunk(file_hash, chunk) do
    case Repo.get_by(ChunkHash, file_hash_id: file_hash.id, hash: chunk) do
      nil ->
        %ChunkHash{}
        |> ChunkHash.changeset(%{hash: chunk, status: "missing", file_hash_id: file_hash.id})
        |> Repo.insert()

      existing_chunk ->
        {:ok, existing_chunk}
    end
  end

  def find_missing_chunks(root_path) do
    query =
      from ch in ChunkHash,
        join: fh in FileHash,
        on: ch.file_hash_id == fh.id,
        join: hr in HashResult,
        on: fh.hash_result_id == hr.id,
        where: hr.root_path == ^root_path and ch.status == "missing",
        select: {hr.id, fh.id, fh.file_name, ch.hash}

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
    ChunkHash
    |> where(file_hash_id: ^file_hash_id)
    |> Repo.all()
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
