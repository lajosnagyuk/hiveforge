defmodule HiveforgeController.Router do
  use Plug.Router

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers,
    parsers: [:json],
    json_decoder: Jason
  )
  plug(:dispatch)

  get("/", do: send_resp(conn, 200, "OK"))
  get("/api/v1/health", do: send_resp(conn, 200, "OK"))
  get("/api/v1/readiness", do: send_resp(conn, 200, "OK"))
# Jobs
  get "/api/v1/jobs", do: HiveforgeController.JobController.call(conn, action: :list_jobs)
  get "/api/v1/jobs/:id", do: HiveforgeController.JobController.call(conn, action: :get_job)

  post "/api/v1/jobs", do: HiveforgeController.JobController.call(conn, action: :create_job)
# Agents
  post "/api/v1/agents/register", do: HiveforgeController.AgentController.call(conn, action: :register)
  post "/api/v1/agents/heartbeat", do: HiveforgeController.AgentController.call(conn, action: :heartbeat)
  get "/api/v1/agents/:id", do: HiveforgeController.AgentController.call(conn, action: :get_agent)
  get "/api/v1/agents", do: HiveforgeController.AgentController.call(conn, action: :list_agents)

  match(_, do: send_resp(conn, 404, "Not Found"))
end
