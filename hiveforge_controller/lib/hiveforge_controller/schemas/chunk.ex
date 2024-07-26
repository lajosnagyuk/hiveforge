defmodule HiveforgeController.Schemas.Chunk do
  use Ecto.Schema
  import Ecto.Changeset

  schema "chunks" do
    field :hash, :string
    field :size, :integer

    many_to_many :file_results, HiveforgeController.Schemas.FileResult, join_through: HiveforgeController.Schemas.FileChunk

    timestamps()
  end

  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [:hash, :size])
    |> validate_required([:hash, :size])
  end
end
