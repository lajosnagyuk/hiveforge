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
    has_many :file_chunk_maps, HiveforgeController.Schemas.FileChunkMap
    has_many :chunk_hashes, through: [:file_chunk_maps, :chunk_hash]

    timestamps()
  end

  def changeset(file_hash, attrs) do
    file_hash
    |> cast(attrs, [:file_name, :chunk_size, :chunk_count, :total_size, :status, :hash_result_id])
    |> validate_required([:file_name, :total_size, :hash_result_id])
  end
end
