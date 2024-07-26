defmodule HiveforgeController.Schemas.DirectoryEntry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "directory_entries" do
    field :path, :string
    field :name, :string

    belongs_to :hash_result, HiveforgeController.Schemas.HashResult

    timestamps()
  end

  def changeset(directory_entry, attrs) do
    directory_entry
    |> cast(attrs, [:path, :name, :hash_result_id])
    |> validate_required([:path, :name, :hash_result_id])
  end
end
