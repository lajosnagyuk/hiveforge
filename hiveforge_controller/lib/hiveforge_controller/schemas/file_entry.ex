defmodule HiveforgeController.Schemas.FileEntry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "file_entries" do
    field :path, :string
    field :file_name, :string
    field :size, :integer
    field :chunk_size, :integer
    field :chunk_count, :integer

    belongs_to :hash_result, HiveforgeController.Schemas.HashResult
    has_many :file_chunks, HiveforgeController.Schemas.FileChunk

    timestamps()
  end

  def changeset(file_entry, attrs) do
    file_entry
    |> cast(attrs, [:path, :file_name, :size, :chunk_size, :chunk_count, :hash_result_id])
    |> validate_required([:path, :file_name, :size, :hash_result_id])
  end
end
