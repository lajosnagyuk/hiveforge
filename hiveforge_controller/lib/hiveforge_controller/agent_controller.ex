defmodule HiveforgeController.AgentController do
  use Plug.Builder
  alias HiveforgeController.{Agent, Repo}
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)
    apply(__MODULE__, action, [conn, conn.params])
  end

  def register(conn, params) do
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
  end

  def heartbeat(conn, %{"agent_id" => agent_id}) do
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
  end

  def list_agents(conn, _params) do
    agents = Repo.all(Agent)
    json_response(conn, agents)
  end

  def get_agent(conn, %{"id" => id}) do
    case Repo.get(Agent, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json_response(%{error: "Agent not found"})
      agent ->
        json_response(conn, agent)
    end
  end

  defp json_response(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(conn.status || 200, Jason.encode!(data))
  end
end
