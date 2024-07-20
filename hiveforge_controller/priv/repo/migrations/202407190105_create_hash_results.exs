defmodule HiveforgeController.Repo.Migrations.CreateHashResults do
  use Ecto.Migration

  def change do
    create table(:hash_results) do
      add :root_path, :string, null: false
      add :total_files, :integer, null: false
      add :total_size, :bigint, null: false
      add :hashing_time, :float, null: false
      add :status, :string, default: "pending", null: false
      timestamps()
    end

    create table(:file_hashes) do
      add :hash_result_id, references(:hash_results, on_delete: :delete_all), null: false
      add :file_name, :string, null: false
      add :chunk_size, :integer
      add :chunk_count, :integer
      add :total_size, :bigint, null: false
      add :status, :string, default: "pending", null: false
      timestamps()
    end

    create table(:chunk_hashes) do
      add :file_hash_id, references(:file_hashes, on_delete: :delete_all), null: false
      add :hash, :string, null: false
      add :status, :string, default: "pending", null: false
      timestamps()
    end

    create index(:file_hashes, [:hash_result_id])
    create index(:chunk_hashes, [:file_hash_id])
    create unique_index(:chunk_hashes, [:file_hash_id, :hash])
  end
end
