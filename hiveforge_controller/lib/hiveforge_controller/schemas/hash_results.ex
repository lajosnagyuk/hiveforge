defmodule HiveforgeController.Schemas.HashResult do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hash_results" do
    field :root_path, :string
    field :total_files, :integer
    field :total_size, :integer
    field :hashing_time, :float
    field :status, :string
    field :s3_key, :string
    field :s3_backend, :string

    has_many :file_entries, HiveforgeController.Schemas.FileEntry

    timestamps()
  end

  def changeset(hash_result, attrs) do
    hash_result
    |> cast(attrs, [:root_path, :total_files, :total_size, :hashing_time, :status, :s3_key, :s3_backend])
    |> validate_required([:root_path, :total_files, :total_size, :hashing_time, :status])
  end
end
