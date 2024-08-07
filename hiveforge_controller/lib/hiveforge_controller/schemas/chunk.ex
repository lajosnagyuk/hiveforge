defmodule HiveforgeController.Schemas.Chunk do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:uid, :string, autogenerate: false}
  @foreign_key_type :string

  schema "chunks" do
    field :hash, :string
    field :size, :integer

    many_to_many :file_results, HiveforgeController.Schemas.FileResult,
      join_through: HiveforgeController.Schemas.FileChunk,
      join_keys: [chunk_uid: :uid, file_result_uid: :uid]

    timestamps()
  end

  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [:uid, :hash, :size])
    |> validate_required([:uid, :hash, :size])
  end
end
