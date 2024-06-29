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

  get "/api/v1/jobs" do
    jobs = HiveforgeController.Execute.list_jobs()
    send_resp(conn, 200, Jason.encode!(jobs))
  end

  post("/api/v1/jobs", do: HiveforgeController.JobController.create_job(conn))
  match(_, do: send_resp(conn, 404, "Mit ni?"))
end
