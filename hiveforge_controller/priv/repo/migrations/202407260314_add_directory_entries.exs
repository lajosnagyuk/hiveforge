defmodule HiveforgeController.Repo.Migrations.CreateDirectoryEntries do
  use Ecto.Migration

  def change do
    create table(:directory_entries) do
      add :path, :string, null: false
      add :name, :string, null: false
      add :hash_result_id, references(:hash_results, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:directory_entries, [:hash_result_id])
  end
end
