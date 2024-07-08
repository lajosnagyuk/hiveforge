defmodule HiveforgeController.Router do
  use Plug.Router

  plug(Plug.Logger)
  plug(:match)
  plug Plug.Session,
    store: :ets,
    key: "_hiveforge_key",
    table: HiveforgeController.SessionStore.table_name()
  plug :fetch_session
  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug(:dispatch)

  get("/", do: send_resp(conn, 200, "OK"))
  get("/api/v1/health", do: send_resp(conn, 200, "OK"))
  get("/api/v1/readiness", do: send_resp(conn, 200, "OK"))
  # Jobs
  get("/api/v1/jobs", do: HiveforgeController.JobController.call(conn, action: :list_jobs))
  get("/api/v1/jobs/:id", do: HiveforgeController.JobController.call(conn, action: :get_job))

  post("/api/v1/jobs", do: HiveforgeController.JobController.call(conn, action: :create_job))
  # Agents
  post("/api/v1/agents/register",
    do: HiveforgeController.AgentController.call(conn, action: :register)
  )

  post("/api/v1/agents/heartbeat",
    do: HiveforgeController.AgentController.call(conn, action: :heartbeat)
  )

  get("/api/v1/agents/:id",
    do: HiveforgeController.AgentController.call(conn, action: :get_agent)
  )

  get("/api/v1/agents", do: HiveforgeController.AgentController.call(conn, action: :list_agents))

  # API Keys
  post("/api/v1/api_keys/generate",
    do: HiveforgeController.ApiKeyController.call(conn, action: :generate_key)
  )

  # JWT funny business
  get "/api/v1/auth/challenge", do: HiveforgeController.AuthController.call(conn, action: :request_challenge)
  post "/api/v1/auth/verify", do: HiveforgeController.AuthController.call(conn, action: :verify_challenge)

  # Nappy clauses
  match(_, do: send_resp(conn, 404, "Not Found"))
end
