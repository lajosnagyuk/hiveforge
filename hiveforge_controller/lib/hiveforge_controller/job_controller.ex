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
    claims = conn.assigns[:current_user]
    with {:ok, decoded} <- decode_body(params),
         {:ok, job} <- JobService.create_job(decoded, claims) do
      Logger.info("New job created - ID: #{job.id}, API Key Hash: #{_auth_key.key_hash}")
      conn
      |> put_status(:created)
      |> put_resp_content_type("application/json")
      |> json_response(job)
    else
      {:error, :invalid_encoding} ->
        error_response(conn, :bad_request, "Invalid base64 encoding")
      {:error, :invalid_json} ->
        error_response(conn, :bad_request, "Invalid JSON")
      {:error, :invalid_attributes, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        error_response(conn, :unprocessable_entity, %{errors: errors})
      {:error, :unauthorized, reason} ->
        error_response(conn, :unauthorized, "Not authorized to create job: #{reason}")
      {:error, :database_error, reason} ->
        error_response(conn, :internal_server_error, "Database error: #{reason}")
      {:error, :unknown_error, reason} ->
        error_response(conn, :internal_server_error, "An unexpected error occurred: #{reason}")
    end
  end

  def list_jobs(conn, _params) do
    claims = conn.assigns[:current_user]

    case JobService.list_jobs(claims) do
      {:ok, jobs} ->
        conn
        |> put_status(:ok)
        |> put_resp_content_type("application/json")
        |> json_response(jobs)

      {:error, :unauthorized} ->
        error_response(conn, :unauthorized, "Not authorized to list jobs")

      {:error, reason} ->
        error_response(conn, :internal_server_error, "Failed to list jobs: #{inspect(reason)}")
    end
  end

  def get_job(conn, %{"id" => id}) do
    claims = conn.assigns[:current_user]
    case JobService.get_job(id, claims) do
      {:ok, job} ->
        conn
        |> put_status(:ok)
        |> put_resp_content_type("application/json")
        |> json_response(job)
      {:error, :not_found, reason} ->
        error_response(conn, :not_found, reason)
      {:error, :unauthorized, reason} ->
        error_response(conn, :unauthorized, "Not authorized to get job: #{reason}")
      {:error, :database_error, reason} ->
        error_response(conn, :internal_server_error, "Database error: #{reason}")
      {:error, :unknown_error, reason} ->
        error_response(conn, :internal_server_error, "An unexpected error occurred: #{reason}")
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
    |> put_resp_content_type("application/json")
    |> json_response(%{error: message})
  end
end
