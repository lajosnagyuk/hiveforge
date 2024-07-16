defmodule HiveforgeController.Repo.Migrations.AddKeyFieldToApiKeys do
  use Ecto.Migration

  def change do
    alter table(:api_keys) do
      add(:key, :text)
    end
  end
end
