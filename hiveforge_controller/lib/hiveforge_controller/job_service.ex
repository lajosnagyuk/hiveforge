defmodule HiveforgeController.JobService do
  alias HiveforgeController.{Job, Repo}
  import Ecto.Query

  def create_job(attrs) do
    %Job{}
    |> Job.changeset(attrs)
    |> Repo.insert()
  end

  def get_job(id) do
    case Repo.get(Job, id) do
      nil -> {:error, :not_found}
      job -> {:ok, job}
    end
  end

  def list_jobs do
    Job
    |> order_by([j], desc: j.inserted_at)
    |> Repo.all()
  end
end
