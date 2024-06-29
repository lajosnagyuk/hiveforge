defmodule HiveforgeController.JobController do
  import Plug.Conn
  alias HiveforgeController.{Job, Repo}

  def create_job(conn) do
    IO.puts("Received params: #{inspect(conn.body_params)}")

    with %{"body" => encoded_body} <- conn.body_params,
         {:ok, decoded} <- Base.decode64(encoded_body),
         {:ok, attrs} <- Jason.decode(decoded),
         {:ok, job} <- create_job_from_attrs(attrs) do
      conn
      |> put_status(:created)
      |> put_resp_content_type("application/json")
      |> send_resp(201, Jason.encode!(job))
    else
      :error ->
        IO.puts("Invalid base64 encoding")
        send_resp(conn, 400, "Invalid base64 encoding")

      {:error, %Jason.DecodeError{} = e} ->
        IO.puts("JSON decode error: #{inspect(e)}")
        send_resp(conn, 400, "Invalid JSON: #{inspect(e)}")

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        IO.puts("Changeset errors: #{inspect(errors)}")
        send_resp(conn, 400, Jason.encode!(%{errors: errors}))

      error ->
        IO.puts("Unexpected error: #{inspect(error)}")
        send_resp(conn, 500, "Internal Server Error")
    end
  end

  defp create_job_from_attrs(attrs) do
    %Job{}
    |> Job.changeset(attrs)
    |> Repo.insert()
  end

  # Keep the debug version for troubleshooting
  def create_job(conn, :debug) do
    IO.puts("Attempting to read body")

    case read_body(conn) do
      {:ok, body, _conn} ->
        IO.inspect(body, label: "Raw Body")

        case Jason.decode(body) do
          {:ok, decoded} ->
            IO.inspect(decoded, label: "Decoded JSON")
            send_resp(conn, 200, "JSON processed successfully")

          {:error, %Jason.DecodeError{} = e} ->
            IO.puts("JSON decode error: #{inspect(e)}")
            send_resp(conn, 400, "Invalid JSON: #{inspect(e)}")
        end

      {:more, _partial_body, _conn} ->
        IO.puts("Body read error: more data needed")
        send_resp(conn, 413, "Request Entity Too Large")

      {:error, reason} ->
        IO.inspect(reason, label: "Body Read Error")
        send_resp(conn, 500, "Internal Server Error: #{inspect(reason)}")
    end
  rescue
    e ->
      IO.inspect(e, label: "Unexpected Error")
      send_resp(conn, 500, "Internal Server Error: #{inspect(e)}")
  end
end
