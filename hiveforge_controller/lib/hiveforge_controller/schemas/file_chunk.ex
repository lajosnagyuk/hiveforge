defmodule HiveforgeController.Schemas.FileChunk do
  use Ecto.Schema
  import Ecto.Changeset
  alias HiveforgeController.Schemas.Type.SanitizedString

  @primary_key {:uid, :string, autogenerate: false}
  @foreign_key_type :string

  schema "file_chunks" do
    field :sequence, :integer
    field :offset, :integer
    field :file_path, SanitizedString

    belongs_to :file_result, HiveforgeController.Schemas.FileResult, foreign_key: :file_result_uid
    belongs_to :chunk, HiveforgeController.Schemas.Chunk, foreign_key: :chunk_uid
    belongs_to :hash_result, HiveforgeController.Schemas.HashResult, foreign_key: :hash_result_uid

    timestamps()
  end

  def changeset(file_chunk, attrs) do
    file_chunk
    |> cast(attrs, [:uid, :sequence, :offset, :file_path, :file_result_uid, :chunk_uid, :hash_result_uid])
    |> validate_required([:uid, :sequence, :offset, :file_path, :file_result_uid, :chunk_uid, :hash_result_uid])
  end
end
