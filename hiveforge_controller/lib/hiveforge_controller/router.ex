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

  get "/api/v1/jobs", do: HiveforgeController.JobController.call(conn, action: :list_jobs)
  get "/api/v1/jobs/:id", do: HiveforgeController.JobController.call(conn, action: :get_job)

  post "/api/v1/jobs", do: HiveforgeController.JobController.call(conn, action: :create_job)

  match(_, do: send_resp(conn, 404, "Not Found"))
end
