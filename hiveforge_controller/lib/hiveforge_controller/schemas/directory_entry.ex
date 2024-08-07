defmodule HiveforgeController.Schemas.DirectoryEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:uid, :string, autogenerate: false}
  @foreign_key_type :string

  schema "directory_entries" do
    field :name, :string
    field :type, :string
    field :size, :integer
    field :path, :string
    field :parent_path, :string

    belongs_to :hash_result, HiveforgeController.Schemas.HashResult, foreign_key: :hash_result_uid
    belongs_to :parent, HiveforgeController.Schemas.DirectoryEntry, foreign_key: :parent_uid
    has_many :children, HiveforgeController.Schemas.DirectoryEntry, foreign_key: :parent_uid
    has_one :file_result, HiveforgeController.Schemas.FileResult, foreign_key: :directory_entry_uid

    timestamps()
  end

  def changeset(directory_entry, attrs) do
    directory_entry
    |> cast(attrs, [:uid, :name, :type, :size, :path, :parent_path, :hash_result_uid, :parent_uid])
    |> validate_required([:uid, :name, :type, :size, :path, :hash_result_uid])
    |> validate_inclusion(:type, ["file", "directory"])
  end
end
