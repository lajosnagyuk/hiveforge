defmodule HiveforgeController.JobService do
  alias HiveforgeController.{Job, Repo, ApiAuth}
  import Ecto.Query

  def create_job(attrs, claims) do
    case ApiAuth.authorize_action(claims, :create_job) do
      :ok ->
        %Job{}
        |> Job.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, job} -> {:ok, job}
          {:error, changeset} -> {:error, :invalid_attributes, changeset}
        end
      {:error, reason} ->
        {:error, :unauthorized, reason}
    end
  rescue
    e in Ecto.QueryError ->
      {:error, :database_error, Exception.message(e)}
    _ ->
      {:error, :unknown_error, "An unexpected error occurred"}
  end

  def get_job(id, claims) do
    case ApiAuth.authorize_action(claims, :get_job) do
      :ok ->
        case Repo.get(Job, id) do
          nil -> {:error, :not_found, "Job not found"}
          job -> {:ok, job}
        end
      {:error, reason} ->
        {:error, :unauthorized, reason}
    end
  rescue
    e in Ecto.QueryError ->
      {:error, :database_error, Exception.message(e)}
    _ ->
      {:error, :unknown_error, "An unexpected error occurred"}
  end

  def list_jobs(claims) do
    case ApiAuth.authorize_action(claims, :list_jobs) do
      :ok ->
        jobs =
          Job
          |> order_by([j], desc: j.inserted_at)
          |> Repo.all()
        {:ok, jobs}
      {:error, reason} -> {:error, :unauthorized, reason}
    end
  rescue
    e in Ecto.QueryError ->
      {:error, :database_error, Exception.message(e)}
    _ ->
      {:error, :unknown_error, "An unexpected error occurred"}
  end
end
