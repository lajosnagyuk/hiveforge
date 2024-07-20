defmodule HiveforgeController.Router do
  use Plug.Router
  require Logger

  def log_headers(conn, _opts) do
    headers = conn.req_headers |> Enum.map(fn {k, v} -> "#{k}: #{v}" end) |> Enum.join("\n")
    Logger.info("Headers in main Router:\n#{headers}")
    conn
  end

  plug(:log_headers)
  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Session,
    store: :ets,
    key: "_hiveforge_key",
    table: HiveforgeController.SessionStore.table_name()
  )
  plug(:fetch_session)
  plug(:maybe_parse_body)
  plug(:dispatch)

  # unauthenticated routes
  get("/", do: send_resp(conn, 200, "OK"))
  get("/api/v1/health", do: send_resp(conn, 200, "OK"))
  get("/api/v1/readiness", do: send_resp(conn, 200, "OK"))

  # JWT authentication routes (takes API key hash)
  get("/api/v1/auth/challenge",
    do: HiveforgeController.AuthController.call(conn, action: :request_challenge)
  )
  post("/api/v1/auth/verify",
    do: HiveforgeController.AuthController.call(conn, action: :verify_challenge)
  )

  # Forward everything else to the ProtectedRouter
  forward("/api/v1", to: HiveforgeController.ProtectedRouter)

  # Catch-all clause
  match(_, do: send_resp(conn, 404, "Not Found"))

  def call(conn, opts) do
    try do
      super(conn, opts)
    rescue
      e ->
        Logger.error("Error in Router: #{Exception.format(:error, e, __STACKTRACE__)}")
        send_resp(conn, 500, "Internal Server Error")
    end
  end

  # Skip body parsing for certain routes, because they may be gzipped, and we don't unzip unprotected calls
  defp maybe_parse_body(conn, _opts) do
    if should_skip_parsing?(conn) do
      Logger.info("Router: Skipping body parsing for request to #{conn.request_path}")
      conn
    else
      Plug.Parsers.call(conn,
        Plug.Parsers.init(
          parsers: [:urlencoded, :json],
          pass: ["*/*"],
          json_decoder: Jason
        )
      )
    end
  end

  defp should_skip_parsing?(conn) do
    String.starts_with?(conn.request_path, "/api/v1/") and
      conn.request_path not in ["/api/v1/auth/challenge", "/api/v1/auth/verify"]
  end
end
