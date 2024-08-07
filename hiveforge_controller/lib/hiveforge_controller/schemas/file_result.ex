defmodule HiveforgeController.Schemas.FileResult do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:uid, :string, autogenerate: false}
  @foreign_key_type :string

  schema "file_results" do
    field :name, :string
    field :size, :integer
    field :hash, :string
    field :algorithm, :string
    field :average_chunk_size, :integer
    field :min_chunk_size, :integer
    field :max_chunk_size, :integer
    field :total_chunks, :integer
    field :path, :string
    field :parent_directory_path, :string

    belongs_to :hash_result, HiveforgeController.Schemas.HashResult, foreign_key: :hash_result_uid
    belongs_to :directory_entry, HiveforgeController.Schemas.DirectoryEntry, foreign_key: :directory_entry_uid
    many_to_many :chunks, HiveforgeController.Schemas.Chunk,
      join_through: HiveforgeController.Schemas.FileChunk,
      join_keys: [file_result_uid: :uid, chunk_uid: :uid]

    timestamps()
  end

  def changeset(file_result, attrs) do
    file_result
    |> cast(attrs, [:uid, :name, :size, :hash, :algorithm, :average_chunk_size, :min_chunk_size, :max_chunk_size, :total_chunks, :path, :parent_directory_path, :hash_result_uid, :directory_entry_uid])
    |> validate_required([:uid, :name, :size, :hash, :algorithm, :average_chunk_size, :min_chunk_size, :max_chunk_size, :total_chunks, :path, :hash_result_uid])
  end
end
