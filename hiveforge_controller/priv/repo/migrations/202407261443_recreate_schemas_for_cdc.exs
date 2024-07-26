defmodule HiveforgeController.Repo.Migrations.CreateNewHashResultStructure do
  use Ecto.Migration

  def change do
    # Drop existing tables
    drop_if_exists table(:file_chunks)
    drop_if_exists table(:chunks)
    drop_if_exists table(:file_entries)
    drop_if_exists table(:directory_entries)
    drop_if_exists table(:hash_results)

    # Create new tables
    create table(:hash_results) do
      add :root_path, :string, null: false
      add :total_size, :bigint, null: false
      add :total_files, :integer, null: false
      add :status, :string, null: false
      add :hashing_time, :float, null: false
      add :s3_key, :string
      add :s3_backend, :string

      timestamps()
    end

    create table(:directory_entries) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :size, :bigint, null: false
      add :path, :string, null: false
      add :hash_result_id, references(:hash_results, on_delete: :delete_all), null: false
      add :parent_id, references(:directory_entries, on_delete: :delete_all)

      timestamps()
    end

    create table(:file_results) do
      add :name, :string, null: false
      add :size, :bigint, null: false
      add :hash, :string, null: false
      add :algorithm, :string, null: false
      add :average_chunk_size, :integer, null: false
      add :min_chunk_size, :integer, null: false
      add :max_chunk_size, :integer, null: false
      add :total_chunks, :integer, null: false
      add :directory_entry_id, references(:directory_entries, on_delete: :delete_all), null: false

      timestamps()
    end

    create table(:chunks) do
      add :hash, :string, null: false
      add :size, :integer, null: false

      timestamps()
    end

    create table(:file_chunks) do
      add :sequence, :integer, null: false
      add :offset, :bigint, null: false
      add :file_result_id, references(:file_results, on_delete: :delete_all), null: false
      add :chunk_id, references(:chunks, on_delete: :delete_all), null: false

      timestamps()
    end

    # Create indexes
    create index(:directory_entries, [:hash_result_id])
    create index(:directory_entries, [:parent_id])
    create index(:file_results, [:directory_entry_id])
    create index(:file_chunks, [:file_result_id])
    create index(:file_chunks, [:chunk_id])
    create unique_index(:file_chunks, [:file_result_id, :sequence])
  end
end
