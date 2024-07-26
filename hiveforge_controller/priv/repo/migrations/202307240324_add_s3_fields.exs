defmodule HiveforgeController.Repo.Migrations.AddS3FieldsToHashResults do
  use Ecto.Migration

  def change do
    alter table(:hash_results) do
      add :s3_key, :string
      add :s3_backend, :string
    end

    alter table(:chunk_hashes) do
      add :s3_key, :string
      add :s3_backend, :string
    end
  end
end
