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

  # unauthenticated routes
  get("/", do: send_resp(conn, 200, "OK"))
  get("/api/v1/health", do: send_resp(conn, 200, "OK"))
  get("/api/v1/readiness", do: send_resp(conn, 200, "OK"))

  # JWT authentication routes (takes API key hash)
  get("/api/v1/auth/challenge", do: HiveforgeController.AuthController.call(conn, action: :request_challenge))
  post("/api/v1/auth/verify", do: HiveforgeController.AuthController.call(conn, action: :verify_challenge))

  # Forward everything else to the ProtectedRouter
  forward("/api/v1", to: HiveforgeController.ProtectedRouter)

  # Nappy clauses
  match(_, do: send_resp(conn, 404, "Not Found"))

end
