defmodule HiveforgeController.Repo.Migrations.CreateFileChunkMaps do
  use Ecto.Migration

  def change do
    create table(:file_chunk_maps) do
      add :sequence, :integer, null: false
      add :file_hash_id, references(:file_hashes, on_delete: :delete_all), null: false
      add :chunk_hash_id, references(:chunk_hashes, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:file_chunk_maps, [:file_hash_id])
    create index(:file_chunk_maps, [:chunk_hash_id])
    create unique_index(:file_chunk_maps, [:file_hash_id, :sequence])
    create unique_index(:file_chunk_maps, [:file_hash_id, :chunk_hash_id])
  end
end
