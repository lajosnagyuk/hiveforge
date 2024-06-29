defmodule HiveforgeController.Execute do
  import Ecto.Query, warn: false
  alias HiveforgeController.Repo
  alias HiveforgeController.Job

  @doc """
  Create a new job.
  """
  def create_job(attrs \\ %{}) do
    %Job{}
    |> Job.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Get a job by ID.
  """
  def get_job!(id) do
    Repo.get!(Job, id)
  end

  @doc """
  List all jobs.
  """
  def list_jobs do
    Job
    |> order_by([j], desc: j.inserted_at)
    |> Repo.all()
  end
end
