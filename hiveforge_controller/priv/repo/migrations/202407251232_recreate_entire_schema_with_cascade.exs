
defmodule HiveforgeController.Repo.Migrations.RecreateEntireSchemaWithCascade do
  use Ecto.Migration

  def change do
    # Drop all existing tables with CASCADE
    execute "DROP TABLE IF EXISTS file_chunks CASCADE"
    execute "DROP TABLE IF EXISTS chunks CASCADE"
    execute "DROP TABLE IF EXISTS file_entries CASCADE"
    execute "DROP TABLE IF EXISTS hash_results CASCADE"
    execute "DROP TABLE IF EXISTS file_hashes CASCADE"
    execute "DROP TABLE IF EXISTS chunk_hashes CASCADE"
    execute "DROP TABLE IF EXISTS file_chunk_maps CASCADE"
    execute "DROP TABLE IF EXISTS file_metadata CASCADE"

    # Recreate hash_results table
    create table(:hash_results) do
      add :root_path, :string, null: false
      add :total_files, :integer, null: false
      add :total_size, :bigint, null: false
      add :hashing_time, :float, null: false
      add :status, :string, null: false
      add :s3_key, :string
      add :s3_backend, :string
      add :directory_structure, :map

      timestamps()
    end

    # Recreate file_entries table
    create table(:file_entries) do
      add :path, :string, null: false
      add :file_name, :string, null: false
      add :size, :integer, null: false
      add :chunk_size, :integer, null: false
      add :chunk_count, :integer, null: false
      add :hash_result_id, references(:hash_results, on_delete: :delete_all), null: false

      timestamps()
    end

    # Recreate chunks table
    create table(:chunks) do
      add :hash, :string, null: false
      add :size, :integer, null: false
      add :status, :string, null: false
      add :s3_key, :string
      add :s3_backend, :string

      timestamps()
    end

    # Recreate file_chunks table
    create table(:file_chunks) do
      add :sequence, :integer, null: false
      add :file_entry_id, references(:file_entries, on_delete: :delete_all), null: false
      add :chunk_id, references(:chunks, on_delete: :delete_all), null: false

      timestamps()
    end

    # Create indexes
    create index(:hash_results, [:root_path])
    create index(:hash_results, [:s3_key])
    create index(:file_entries, [:hash_result_id])
    create index(:file_entries, [:file_name])
    create unique_index(:chunks, [:hash])
    create index(:chunks, [:s3_key])
    create index(:file_chunks, [:file_entry_id])
    create index(:file_chunks, [:chunk_id])
    create unique_index(:file_chunks, [:file_entry_id, :sequence])
    create unique_index(:file_chunks, [:file_entry_id, :chunk_id])
  end
end
