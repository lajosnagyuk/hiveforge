defmodule HiveforgeAgent.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting application...")

    children = [
      {HiveforgeAgent.Scheduler, []}
    ]

    opts = [strategy: :one_for_one, name: HiveforgeAgent.Supervisor]
    Supervisor.start_link(children, opts)
  rescue
    e ->
      Logger.error("Application failed to start: #{inspect(e)}")
      raise e
  end
end
