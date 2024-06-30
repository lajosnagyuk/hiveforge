defmodule HiveforgeController.JobController do
  import Plug.Conn
  alias HiveforgeController.JobService

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)
    apply(__MODULE__, action, [conn, conn.params])
  end

  def create_job(conn, params) do
    with {:ok, decoded} <- decode_body(params),
         {:ok, job} <- JobService.create_job(decoded) do
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
        error_response(conn, :bad_request, %{errors: errors})
    end
  end

  def list_jobs(conn, _params) do
    jobs = JobService.list_jobs()
    json_response(conn, jobs)
  end

  def get_job(conn, %{"id" => id}) do
    case JobService.get_job(String.to_integer(id)) do
      {:ok, job} ->
        conn
        |> put_status(:ok)
        |> json_response(job)
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json_response(%{error: "Job not found"})
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
