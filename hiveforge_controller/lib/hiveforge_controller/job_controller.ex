defmodule HiveforgeController.JobController do
  use Plug.Builder
  alias HiveforgeController.{JobService, ApiAuth, Repo}
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)
    apply(__MODULE__, action, [conn, conn.params])
  end

  def create_job(conn, params) do
    with {:ok, _auth_key} <- ApiAuth.validate_request(conn, params, :create_job),
         {:ok, decoded} <- decode_body(params),
         {:ok, job} <- JobService.create_job(decoded) do
      Logger.info("New job created - ID: #{job.id}, API Key Hash: #{_auth_key.key_hash}")
      conn
      |> put_status(:created)
      |> json_response(job)
    else
      {:error, :invalid_encoding} ->
        error_response(conn, :bad_request, "Invalid base64 encoding")
      {:error, :invalid_json} ->
        error_response(conn, :bad_request, "Invalid JSON")
      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        error_response(conn, :unprocessable_entity, %{errors: errors})
      {:error, reason} ->
        error_response(conn, :unauthorized, reason)
    end
  end

  def list_jobs(conn, params) do
    with {:ok, _auth_key} <- ApiAuth.validate_request(conn, params, :list_jobs) do
      jobs = JobService.list_jobs()
      json_response(conn, jobs)
    else
      {:error, reason} ->
        error_response(conn, :unauthorized, reason)
    end
  end

  def get_job(conn, %{"id" => id} = params) do
    with {:ok, _auth_key} <- ApiAuth.validate_request(conn, params, :get_job),
         {:ok, job} <- JobService.get_job(String.to_integer(id)) do
      conn
      |> put_status(:ok)
      |> json_response(job)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json_response(%{error: "Job not found"})
      {:error, reason} ->
        error_response(conn, :unauthorized, reason)
    end
  end

  defp decode_body(%{"body" => encoded_body}) do
    with {:ok, decoded} <- Base.decode64(encoded_body),
         {:ok, attrs} <- Jason.decode(decoded) do
      {:ok, attrs}
    else
      :error -> {:error, :invalid_encoding}
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
    end
  end
  defp decode_body(_), do: {:error, :invalid_encoding}

  defp json_response(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(conn.status || 200, Jason.encode!(data))
  end

  defp error_response(conn, status, message) do
    conn
    |> put_status(status)
    |> json_response(%{error: message})
  end
end
