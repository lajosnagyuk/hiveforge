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
