defmodule HiveforgeController.ApiKey do
  use Ecto.Schema
  import Ecto.Changeset
  alias HiveforgeController.Common

  schema "api_keys" do
    field(:key, :string)
    field(:key_hash, :string)
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
    |> put_key_hash()
    |> unique_constraint(:key_hash)
  end

  defp put_key_hash(changeset) do
    case get_change(changeset, :key) do
      nil -> changeset
      key -> put_change(changeset, :key_hash, Common.hash_key(key))
    end
  end
end
