defmodule HiveforgeController.ProtectedRouter do
  use Plug.Router
  require Logger

  plug(:log_protected_request)
  plug(:log_headers)
  plug(HiveforgeController.JWTAuthPlug)
  plug(HiveforgeController.DebugPlug)
  plug(HiveforgeController.GzipDecompressor)
  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason,
    length: 100_000_000
  )
  plug(:match)
  plug(:dispatch)

  def log_protected_request(conn, _opts) do
    Logger.info("ProtectedRouter: Request received")
    Logger.info("ProtectedRouter: Path: #{conn.request_path}")
    Logger.info("ProtectedRouter: Method: #{conn.method}")
    conn
  end

  def log_headers(conn, _opts) do
    headers = conn.req_headers |> Enum.map(fn {k, v} -> "#{k}: #{v}" end) |> Enum.join("\n")
    Logger.info("ProtectedRouter: Headers:\n#{headers}")
    conn
  end


  post("/hash-results", do:
    HiveforgeController.Controllers.HashController.call(conn, action: :receive_hash)
  )


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

  # Don't cross the yellow line
  def call(conn, opts) do
    try do
      super(conn, opts)
    rescue
      e ->
        Logger.error("Error in ProtectedRouter: #{Exception.format(:error, e, __STACKTRACE__)}")
        send_resp(conn, 500, "Internal Server Error")
    end
  end
end
