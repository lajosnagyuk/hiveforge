defmodule HiveforgeController.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    internal_service_port = System.get_env("HIVEFORGE_CONTROLLER_INTERNAL_SERVICE_PORT") || "4000"

    # Determine the scheme and options based on TLS_TERMINATION_METHOD
    {scheme, options} =
      case System.get_env("TLS_TERMINATION_METHOD") do
        "service" ->
          {:http, [port: String.to_integer(internal_service_port)]}

        "internal" ->
          {:https,
           [
             port: String.to_integer(internal_service_port),
             cipher_suite: :strong,
             certfile: System.get_env("HIVEFORGE_CONTROLLER_CERTFILE"),
             keyfile: System.get_env("HIVEFORGE_CONTROLLER_KEYFILE")
           ]}

        _ ->
          {:http, [port: String.to_integer(internal_service_port)]}
      end

    children = [
      {
        Plug.Cowboy,
        scheme: scheme, plug: HiveforgeController.Router, options: options
      },
      HiveforgeController.Repo,
      HiveforgeController.AgentMonitor,
      HiveforgeController.SessionStore
    ]

    opts = [strategy: :one_for_one, name: HiveforgeController.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
