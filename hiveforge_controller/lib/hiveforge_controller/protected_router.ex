defmodule HiveforgeController.ProtectedRouter do
  import HiveforgeController.JWTAuthPlug
  use Plug.Router
  require Logger

  def log_headers(conn, _opts) do
    headers = conn.req_headers |> Enum.map(fn {k, v} -> "#{k}: #{v}" end) |> Enum.join("\n")
    Logger.info("Headers in ProtectedRouter:\n#{headers}")
    conn
  end

  plug(:log_headers)
  plug(HiveforgeController.JWTAuthPlug)
  plug(:match)
  plug(:dispatch)

  # Jobs
  get("/jobs", do: HiveforgeController.JobController.call(conn, action: :list_jobs))
  get("/jobs/:id", do: HiveforgeController.JobController.call(conn, action: :get_job))
  post("/jobs", do: HiveforgeController.JobController.call(conn, action: :create_job))

  # Agents
  post("/agents/register",
    do: HiveforgeController.AgentController.call(conn, action: :register)
  )

  post("/agents/heartbeat",
    do: HiveforgeController.AgentController.call(conn, action: :heartbeat)
  )

  get("/agents/:id",
    do: HiveforgeController.AgentController.call(conn, action: :get_agent)
  )

  get("/agents", do: HiveforgeController.AgentController.call(conn, action: :list_agents))

  # API Keys
  post("/api_keys/generate",
    do: HiveforgeController.ApiKeyController.call(conn, action: :generate_key)
  )

  # Good Bye Path
  match(_, do: send_resp(conn, 404, "Not Found"))
end
