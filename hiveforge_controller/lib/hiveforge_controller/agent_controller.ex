defmodule HiveforgeController.AgentController do
  use Plug.Builder
  alias HiveforgeController.AgentService
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)
    apply(__MODULE__, action, [conn, conn.params])
  end

  def register(conn, params) do
    claims = conn.assigns[:current_user]

    case AgentService.register_agent(params, claims) do
      {:ok, agent} ->
        Logger.info("New agent registered - ID: #{agent.id}, JWT Type: #{claims["type"]}")

        conn
        |> put_status(:created)
        |> json_response(agent)

      {:error, :unauthorized, reason} ->
        Logger.warn("Agent registration failed - Unauthorized: #{reason}")
        error_response(conn, :unauthorized, reason)

      {:error, :validation_error, errors} ->
        Logger.warn("Agent registration failed - Validation errors: #{inspect(errors)}")
        error_response(conn, :unprocessable_entity, errors)

      {:error, reason, message} ->
        Logger.warn("Agent registration failed - Reason: #{reason}, Message: #{message}")
        error_response(conn, :internal_server_error, message)
    end
  end

  def heartbeat(conn, %{"agent_id" => agent_id}) do
    claims = conn.assigns[:current_user]

    case AgentService.update_heartbeat(agent_id, claims) do
      {:ok, updated_agent} ->
        Logger.info(
          "Agent heartbeat received - ID: #{updated_agent.id}, JWT Type: #{claims["type"]}"
        )

        conn
        |> put_status(:ok)
        |> json_response(%{message: "Heartbeat received", agent: updated_agent})

      {:error, :not_found, message} ->
        error_response(conn, :not_found, message)

      {:error, :unauthorized, reason} ->
        error_response(conn, :unauthorized, reason)

      {:error, reason, message} ->
        Logger.warn(
          "Agent heartbeat failed - ID: #{agent_id}, Reason: #{reason}, Message: #{message}"
        )

        error_response(conn, :internal_server_error, message)
    end
  end

  def list_agents(conn, _params) do
    claims = conn.assigns[:current_user]

    case AgentService.list_agents(claims) do
      {:ok, agents} ->
        conn
        |> put_status(:ok)
        |> json_response(agents)

      {:error, :unauthorized, reason} ->
        error_response(conn, :unauthorized, reason)

      {:error, reason, message} ->
        error_response(conn, :internal_server_error, message)
    end
  end

  def get_agent(conn, %{"id" => id}) do
    claims = conn.assigns[:current_user]

    case AgentService.get_agent(id, claims) do
      {:ok, agent} ->
        conn
        |> put_status(:ok)
        |> json_response(agent)

      {:error, :not_found, message} ->
        error_response(conn, :not_found, message)

      {:error, :unauthorized, reason} ->
        error_response(conn, :unauthorized, reason)

      {:error, reason, message} ->
        error_response(conn, :internal_server_error, message)
    end
  end

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
