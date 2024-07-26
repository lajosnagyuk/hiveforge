defmodule HiveforgeController.Repo.Migrations.RemoveDirectoryStructureFromHashResults do
  use Ecto.Migration

  def change do
    alter table(:hash_results) do
      remove :directory_structure
    end
  end
end
