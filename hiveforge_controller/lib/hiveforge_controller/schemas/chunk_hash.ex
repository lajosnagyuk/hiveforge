defmodule HiveforgeController.Schemas.ChunkHash do
  use Ecto.Schema
  import Ecto.Changeset

  schema "chunk_hashes" do
    field :hash, :string
    field :status, :string, default: "pending"

    has_many :file_chunk_maps, HiveforgeController.Schemas.FileChunkMap
    has_many :file_hashes, through: [:file_chunk_maps, :file_hash]

    timestamps()
  end

  def changeset(chunk_hash, attrs) do
    chunk_hash
    |> cast(attrs, [:hash, :status])
    |> validate_required([:hash])
    |> unique_constraint(:hash)
  end
end
