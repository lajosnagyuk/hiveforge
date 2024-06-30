defmodule HiveforgeController.Repo.Migrations.CreateAgents do
  use Ecto.Migration

  def change do
    create table(:agents) do
      add :name, :string, null: false
      add :agent_id, :string, null: false
      add :capabilities, {:array, :string}, null: false
      add :status, :string, default: "active"
      timestamps()
    end

    create unique_index(:agents, [:agent_id])
  end
end
