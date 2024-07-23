defmodule HiveforgeController.Schemas.FileChunkMap do
  use Ecto.Schema
  import Ecto.Changeset

  schema "file_chunk_maps" do
    field :sequence, :integer

    belongs_to :file_hash, HiveforgeController.Schemas.FileHash
    belongs_to :chunk_hash, HiveforgeController.Schemas.ChunkHash

    timestamps()
  end

  def changeset(file_chunk_map, attrs) do
    file_chunk_map
    |> cast(attrs, [:sequence, :file_hash_id, :chunk_hash_id])
    |> validate_required([:sequence, :file_hash_id, :chunk_hash_id])
    |> unique_constraint([:file_hash_id, :sequence])
    |> unique_constraint([:file_hash_id, :chunk_hash_id])
  end
end
