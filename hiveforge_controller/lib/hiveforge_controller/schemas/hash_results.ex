defmodule HiveforgeController.Schemas.HashResult do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:uid, :string, autogenerate: false}
  @foreign_key_type :string

  schema "hash_results" do
    field :root_path, :string
    field :total_size, :integer
    field :total_files, :integer
    field :hashing_time, :float
    field :status, :string
    field :s3_key, :string
    field :s3_backend, :string

    has_many :directory_entries, HiveforgeController.Schemas.DirectoryEntry, foreign_key: :hash_result_uid
    has_many :file_results, HiveforgeController.Schemas.FileResult, foreign_key: :hash_result_uid

    timestamps()
  end

  def changeset(hash_result, attrs) do
    hash_result
    |> cast(attrs, [:uid, :root_path, :total_size, :total_files, :hashing_time, :status, :s3_key, :s3_backend])
    |> validate_required([:uid, :root_path, :total_size, :total_files, :hashing_time])
  end
end
