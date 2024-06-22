defmodule HiveforgeController.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {
        Plug.Cowboy,
        # read certfile and keyfile paths from environment variables
        scheme: :https,
        plug: HiveforgeController.Router,
        options: [
          port: 4000,
          cipher_suite: :strong,
          certfile: System.get_env("HIVEFORGE_CONTROLLER_CERTFILE"),
          keyfile: System.get_env("HIVEFORGE_CONTROLLER_KEYFILE")
        ]
      }
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HiveforgeController.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
