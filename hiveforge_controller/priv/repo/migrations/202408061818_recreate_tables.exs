defmodule HiveforgeController.Repo.Migrations.RecreateTablesWithStringUids do
  use Ecto.Migration

  def change do
    # Drop existing tables with cascade
    drop table(:file_chunks, cascade: true)
    drop table(:chunks, cascade: true)
    drop table(:file_results, cascade: true)
    drop table(:directory_entries, cascade: true)
    drop table(:hash_results, cascade: true)

    # Recreate tables with string-based UIDs
    create table(:hash_results, primary_key: false) do
      add :uid, :string, primary_key: true
      add :root_path, :string, null: false
      add :total_size, :bigint, null: false
      add :total_files, :integer, null: false
      add :hashing_time, :float, null: false
      add :status, :string, null: false
      add :s3_key, :string
      add :s3_backend, :string

      timestamps()
    end

    create table(:directory_entries, primary_key: false) do
      add :uid, :string, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false
      add :size, :bigint, null: false
      add :path, :string, null: false
      add :parent_path, :string
      add :hash_result_uid, references(:hash_results, column: :uid, type: :string), null: false
      add :parent_uid, references(:directory_entries, column: :uid, type: :string)

      timestamps()
    end

    create table(:file_results, primary_key: false) do
      add :uid, :string, primary_key: true
      add :name, :string, null: false
      add :size, :bigint, null: false
      add :hash, :string, null: false
      add :algorithm, :string, null: false
      add :average_chunk_size, :integer, null: false
      add :min_chunk_size, :integer, null: false
      add :max_chunk_size, :integer, null: false
      add :total_chunks, :integer, null: false
      add :path, :string, null: false
      add :parent_directory_path, :string
      add :hash_result_uid, references(:hash_results, column: :uid, type: :string), null: false
      add :directory_entry_uid, references(:directory_entries, column: :uid, type: :string)

      timestamps()
    end

    create table(:chunks, primary_key: false) do
      add :uid, :string, primary_key: true
      add :hash, :string, null: false
      add :size, :integer, null: false

      timestamps()
    end

    create table(:file_chunks, primary_key: false) do
      add :uid, :string, primary_key: true
      add :sequence, :integer, null: false
      add :offset, :bigint, null: false
      add :file_path, :string, null: false
      add :file_result_uid, references(:file_results, column: :uid, type: :string), null: false
      add :chunk_uid, references(:chunks, column: :uid, type: :string), null: false
      add :hash_result_uid, references(:hash_results, column: :uid, type: :string), null: false

      timestamps()
    end

    # Create indexes
    create index(:directory_entries, [:hash_result_uid])
    create index(:directory_entries, [:parent_uid])
    create index(:file_results, [:hash_result_uid])
    create index(:file_results, [:directory_entry_uid])
    create unique_index(:chunks, [:hash])
    create index(:file_chunks, [:file_result_uid])
    create index(:file_chunks, [:chunk_uid])
    create index(:file_chunks, [:hash_result_uid])
  end
end
