defmodule HiveforgeController.Job do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :description,
             :status,
             :requested_capabilities,
             :inserted_at,
             :updated_at
           ]}
  schema "job" do
    field(:name, :string)
    field(:description, :string)
    field(:status, :string)
    field(:requested_capabilities, {:array, :string})
    timestamps()
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [:name, :description, :status, :requested_capabilities])
    |> validate_required([:name, :description, :status, :requested_capabilities])
  end
end
