defmodule HiveforgeController.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :name, :agent_id, :capabilities, :status, :last_heartbeat, :inserted_at, :updated_at]}
  schema "agents" do
    field :name, :string
    field :agent_id, :string
    field :capabilities, {:array, :string}
    field :status, :string
    field :last_heartbeat, :naive_datetime
    timestamps()
  end

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [:name, :agent_id, :capabilities, :status, :last_heartbeat])
    |> validate_required([:name, :agent_id, :capabilities])
    |> unique_constraint(:agent_id)
  end
end
