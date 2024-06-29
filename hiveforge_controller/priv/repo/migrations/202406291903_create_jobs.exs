defmodule HiveforgeController.Repo.Migrations.CreateJobs do
  use Ecto.Migration

  def change do
    create table(:job) do
      add(:name, :string)
      add(:description, :string)
      add(:status, :string)
      add(:requested_capabilities, {:array, :string})

      timestamps()
    end
  end
end
