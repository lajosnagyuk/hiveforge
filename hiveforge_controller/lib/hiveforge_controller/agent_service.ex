defmodule HiveforgeController.AgentService do
  alias HiveforgeController.{Repo, Agent, ApiKeyService}
  import Ecto.Query

  def register_agent(params, claims) do
    case ApiKeyService.authorize_action(claims, :register_agent) do
      :ok ->
        %Agent{}
        |> Agent.changeset(params)
        |> Repo.insert()

      {:error, reason} ->
        {:error, :unauthorized, reason}
    end
  rescue
    Ecto.ConstraintError ->
      {:error, :constraint_error, "Agent ID must be unique"}

    e in Ecto.ChangestError ->
      {:error, :validation_error, e.message}

    _ ->
      {:error, :unknown_error, "An unexpected error occurred"}
  end

  def update_heartbeat(agent_id, claims) do
    case ApiKeyService.authorize_action(claims, :update_heartbeat) do
      :ok ->
        Agent
        |> Repo.get_by(agent_id: agent_id)
        |> case do
          nil ->
            {:error, :not_found, "Agent not found"}

          agent ->
            agent
            |> Agent.changeset(%{last_heartbeat: DateTime.utc_now(), status: "active"})
            |> Repo.update()
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

  def list_agents(claims) do
    case ApiKeyService.authorize_action(claims, :list_agents) do
      :ok ->
        agents =
          Agent
          |> order_by([a], desc: a.inserted_at)
          |> Repo.all()

        {:ok, agents}

      {:error, reason} ->
        {:error, :unauthorized, reason}
    end
  rescue
    e in Ecto.QueryError ->
      {:error, :database_error, Exception.message(e)}

    _ ->
      {:error, :unknown_error, "An unexpected error occurred"}
  end

  def get_agent(id, claims) do
    case ApiKeyService.authorize_action(claims, :get_agent) do
      :ok ->
        case Repo.get(Agent, id) do
          nil -> {:error, :not_found, "Agent not found"}
          agent -> {:ok, agent}
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
end
