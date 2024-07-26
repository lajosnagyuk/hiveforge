defmodule HiveforgeController.Schemas.FileChunk do
  use Ecto.Schema
  import Ecto.Changeset

  schema "file_chunks" do
    field :sequence, :integer

    belongs_to :file_entry, HiveforgeController.Schemas.FileEntry
    belongs_to :chunk, HiveforgeController.Schemas.Chunk

    timestamps()
  end

  def changeset(file_chunk, attrs) do
    file_chunk
    |> cast(attrs, [:sequence, :file_entry_id, :chunk_id])
    |> validate_required([:sequence, :file_entry_id, :chunk_id])
    |> unique_constraint([:file_entry_id, :sequence])
  end
end
