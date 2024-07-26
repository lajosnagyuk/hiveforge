defmodule HiveforgeController.Schemas.Chunk do
  use Ecto.Schema
  import Ecto.Changeset

  schema "chunks" do
    field :hash, :string
    field :size, :integer
    field :status, :string
    field :s3_key, :string
    field :s3_backend, :string

    has_many :file_chunks, HiveforgeController.Schemas.FileChunk

    timestamps()
  end

  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [:hash, :size, :status, :s3_key, :s3_backend])
    |> validate_required([:hash, :status])
    |> unique_constraint(:hash)
  end
end
