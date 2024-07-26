defmodule HiveforgeController.Schemas.DirectoryEntry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "directory_entries" do
    field :name, :string
    field :type, :string
    field :size, :integer
    field :path, :string

    belongs_to :hash_result, HiveforgeController.Schemas.HashResult
    belongs_to :parent, HiveforgeController.Schemas.DirectoryEntry
    has_many :children, HiveforgeController.Schemas.DirectoryEntry, foreign_key: :parent_id
    has_one :file_result, HiveforgeController.Schemas.FileResult

    timestamps()
  end

  def changeset(directory_entry, attrs) do
    directory_entry
    |> cast(attrs, [:name, :type, :size, :path, :hash_result_id, :parent_id])
    |> validate_required([:name, :type, :size, :path, :hash_result_id])
    |> validate_inclusion(:type, ["file", "directory"])
  end
end
