defmodule HiveforgeController.Schemas.FileChunk do
  use Ecto.Schema
  import Ecto.Changeset

  schema "file_chunks" do
    field :sequence, :integer
    field :offset, :integer

    belongs_to :file_result, HiveforgeController.Schemas.FileResult
    belongs_to :chunk, HiveforgeController.Schemas.Chunk

    timestamps()
  end

  def changeset(file_chunk, attrs) do
    file_chunk
    |> cast(attrs, [:sequence, :offset, :file_result_id, :chunk_id])
    |> validate_required([:sequence, :offset, :file_result_id, :chunk_id])
  end
end
