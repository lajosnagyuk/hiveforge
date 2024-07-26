defmodule HiveforgeController.Schemas.FileResult do
  use Ecto.Schema
  import Ecto.Changeset

  schema "file_results" do
    field :name, :string
    field :size, :integer
    field :hash, :string
    field :algorithm, :string
    field :average_chunk_size, :integer
    field :min_chunk_size, :integer
    field :max_chunk_size, :integer
    field :total_chunks, :integer

    belongs_to :directory_entry, HiveforgeController.Schemas.DirectoryEntry
    many_to_many :chunks, HiveforgeController.Schemas.Chunk, join_through: HiveforgeController.Schemas.FileChunk

    timestamps()
  end

  def changeset(file_result, attrs) do
    file_result
    |> cast(attrs, [:name, :size, :hash, :algorithm, :average_chunk_size, :min_chunk_size, :max_chunk_size, :total_chunks, :directory_entry_id])
    |> validate_required([:name, :size, :hash, :algorithm, :average_chunk_size, :min_chunk_size, :max_chunk_size, :total_chunks, :directory_entry_id])
  end
end
