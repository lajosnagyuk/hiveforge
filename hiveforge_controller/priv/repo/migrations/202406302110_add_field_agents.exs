defmodule HiveforgeController.Repo.Migrations.AddLastHeartbeatToAgents do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add :last_heartbeat, :naive_datetime
    end
  end
end
