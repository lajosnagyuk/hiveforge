defmodule HiveforgeController.AgentController do
  use Plug.Builder
  alias HiveforgeController.{Agent, Repo, ApiAuth}
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)
    apply(__MODULE__, action, [conn, conn.params])
  end

  def register(conn, params) do
    with {:ok, _api_key} <- ApiAuth.validate_request(conn, params, :register),
         changeset = Agent.changeset(%Agent{}, params),
         {:ok, agent} <- Repo.insert(changeset) do
      Logger.info("New agent registered - ID: #{agent.id}, API Key Type: #{_api_key.type}, Hash: #{_api_key.key_hash}")
      conn
      |> put_status(:created)
      |> json_response(agent)
    else
      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        Logger.warn("Agent registration failed - Errors: #{inspect(errors)}")
        conn
        |> put_status(:unprocessable_entity)
        |> json_response(%{errors: errors})
      {:error, reason} ->
        Logger.warn("Agent registration failed - Reason: #{inspect(reason)}")
        conn
        |> put_status(:unauthorized)
        |> json_response(%{error: reason})
    end
  end


  def heartbeat(conn, %{"agent_id" => agent_id} = params) do
    with {:ok, auth_key} <- ApiAuth.validate_request(conn, params, :heartbeat),
         {:ok, agent} <- Repo.get_by(Agent, agent_id: agent_id),
         changeset = Agent.changeset(agent, %{
            last_heartbeat: DateTime.utc_now(),
            status: "active"
         }),
         {:ok, updated_agent} <- Repo.update(changeset) do
      conn
      |> put_status(:ok)
      |> json_response(%{message: "Heartbeat received", agent: updated_agent})
      Logger.info("Agent heartbeat received - ID: #{agent.id}, API Key Hash: #{auth_key.key_hash}")
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json_response(%{error: "Agent not found"})
      {:error, reason} ->
        Logger.warn("Agent heartbeat failed - ID: #{agent_id}, Reason: #{inspect(reason)}")
        conn
        |> put_status(:internal_server_error)
        |> json_response(%{error: "Failed to update agent heartbeat"})
    end
  end

  def list_agents(conn, params) do
    with {:ok, auth_key} <- ApiAuth.validate_request(conn, params, :list_agents) do
      agents = Repo.all(Agent)
      conn
      |> put_status(:ok)
      |> json_response(agents)
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json_response(%{error: reason})
    end
  end

  def get_agent(conn, %{"id" => id} = params) do
    with {:ok, auth_key} <- ApiAuth.validate_request(conn, params, :get_agent),
         {:ok, agent} <- Repo.get(Agent, id) do
      conn
      |> put_status(:ok)
      |> json_response(agent)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json_response(%{error: "Agent not found"})
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json_response(%{error: reason})
    end
  end

  defp authorize_action(%{type: "operator_key"}, _action), do: :ok
  defp authorize_action(%{type: "agent_key"}, action) when action in [:register, :heartbeat], do: :ok
  defp authorize_action(%{type: "reader_key"}, action) when action in [:list_agents, :get_agent], do: :ok
  defp authorize_action(_, _), do: {:error, "Unauthorized action for this key type"}

  defp json_response(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(conn.status || 200, Jason.encode!(data))
  end
end
