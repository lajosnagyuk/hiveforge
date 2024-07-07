defmodule HiveforgeController.ApiKey do
  use Ecto.Schema
  import Ecto.Changeset

  schema "api_keys" do
    field(:key, :string)
    field(:type, :string)
    field(:name, :string)
    field(:description, :string)
    field(:expires_at, :utc_datetime)
    field(:last_used_at, :utc_datetime)
    field(:revoked_at, :utc_datetime)
    field(:created_by, :string)

    belongs_to(:agent, HiveforgeController.Agent)

    timestamps()
  end

  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [
      :key,
      :type,
      :name,
      :description,
      :agent_id,
      :expires_at,
      :last_used_at,
      :revoked_at,
      :created_by
    ])
    |> validate_required([:key, :type])
    |> validate_inclusion(:type, ["operator_key", "agent_key", "reader_key"])
    |> unique_constraint(:key)
  end
end
