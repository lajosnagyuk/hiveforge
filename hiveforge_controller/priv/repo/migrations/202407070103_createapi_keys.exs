defmodule HiveforgeController.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys) do
      add(:key, :string, null: false)
      add(:type, :string, null: false)
      add(:name, :string)
      add(:description, :string)
      add(:agent_id, references(:agents, on_delete: :delete_all))
      add(:expires_at, :utc_datetime)
      add(:last_used_at, :utc_datetime)
      add(:revoked_at, :utc_datetime)
      add(:created_by, :string)

      timestamps()
    end

    create(unique_index(:api_keys, [:key]))
    create(index(:api_keys, [:agent_id]))
    create(index(:api_keys, [:type]))

    # Add a check constraint for the new key types
    create(
      constraint("api_keys", :valid_key_type,
        check: "type IN ('operator_key', 'agent_key', 'reader_key')"
      )
    )
  end
end
