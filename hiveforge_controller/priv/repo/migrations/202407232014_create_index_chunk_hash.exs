defmodule HiveforgeController.Repo.Migrations.AddIndexesToChunkHashes do
  use Ecto.Migration

  def change do
    create index(:chunk_hashes, [:status])
  end
end
