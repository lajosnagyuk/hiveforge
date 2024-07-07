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
    with {:ok, auth_key} <- ApiAuth.validate_request(conn, params),
         :ok <- authorize_action(auth_key, :register) do
      changeset = Agent.changeset(%Agent{}, params)
      case Repo.insert(changeset) do
        {:ok, agent} ->
          conn
          |> put_status(:created)
          |> json_response(agent)
        {:error, changeset} ->
          errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          conn
          |> put_status(:unprocessable_entity)
          |> json_response(%{errors: errors})
      end
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json_response(%{error: reason})
    end
  end

  def heartbeat(conn, %{"agent_id" => agent_id} = params) do
    with {:ok, auth_key} <- ApiAuth.validate_request(conn, params),
         :ok <- authorize_action(auth_key, :heartbeat) do
      case Repo.get_by(Agent, agent_id: agent_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json_response(%{error: "Agent not found"})
        agent ->
          changeset = Agent.changeset(agent, %{
            last_heartbeat: DateTime.utc_now(),
            status: "active"
          })
          case Repo.update(changeset) do
            {:ok, updated_agent} ->
              json_response(conn, %{message: "Heartbeat received", agent: updated_agent})
            {:error, _changeset} ->
              conn
              |> put_status(:internal_server_error)
              |> json_response(%{error: "Failed to update agent heartbeat"})
          end
      end
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json_response(%{error: reason})
    end
  end

  def list_agents(conn, params) do
    with {:ok, auth_key} <- ApiAuth.validate_request(conn, params),
         :ok <- authorize_action(auth_key, :list_agents) do
      agents = Repo.all(Agent)
      json_response(conn, agents)
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json_response(%{error: reason})
    end
  end

  def get_agent(conn, %{"id" => id} = params) do
    with {:ok, auth_key} <- ApiAuth.validate_request(conn, params),
         :ok <- authorize_action(auth_key, :get_agent) do
      case Repo.get(Agent, id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json_response(%{error: "Agent not found"})
        agent ->
          json_response(conn, agent)
      end
    else
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
