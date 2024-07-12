defmodule HiveforgeController.ProtectedRouter do
  use Plug.Router

  plug HiveForgeController.JWTAuthPlug
  plug :match
  plug :dispatch

  # Jobs
  get("/api/v1/jobs", do: HiveforgeController.JobController.call(conn, action: :list_jobs))
  get("/api/v1/jobs/:id", do: HiveforgeController.JobController.call(conn, action: :get_job))
  post("/api/v1/jobs", do: HiveforgeController.JobController.call(conn, action: :create_job))

  # Agents
  post("/api/v1/agents/register", do: HiveforgeController.AgentController.call(conn, action: :register))
  post("/api/v1/agents/heartbeat", do: HiveforgeController.AgentController.call(conn, action: :heartbeat))

  get("/api/v1/agents/:id", do: HiveforgeController.AgentController.call(conn, action: :get_agent))
  get("/api/v1/agents", do: HiveforgeController.AgentController.call(conn, action: :list_agents))

  # API Keys
  post("/api/v1/api_keys/generate",
    do: HiveforgeController.ApiKeyController.call(conn, action: :generate_key)
  )

  # Good Bye Path
  match(_, do: send_resp(conn, 404, "Not Found"))

end
