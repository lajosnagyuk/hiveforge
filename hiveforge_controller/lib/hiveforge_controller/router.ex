defmodule HiveforgeController.Router do
  use Plug.Router

  plug(Plug.Logger)

  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  get("/", do: send_resp(conn, 200, "OK"))

  get("/api/v1/health", do: send_resp(conn, 200, "OK"))
  get("/api/v1/readiness", do: send_resp(conn, 200, "OK"))
  get("/api/v1/activejobs", do: send_resp(conn, 200, "OK"))

  match(_, do: send_resp(conn, 404, "Mit ni?"))
end
