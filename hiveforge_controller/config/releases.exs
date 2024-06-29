import Config

config :hiveforge_controller, HiveforgeController.Repo,
  username: System.get_env("PGPOOL_USERNAME"),
  password: System.get_env("PGPOOL_PASSWORD"),
  database: System.get_env("PGPOOL_DATABASE"),
  hostname: System.get_env("PGPOOL_HOST"),
  port: String.to_integer(System.get_env("PGPOOL_PORT") || "5432"),
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

config :hiveforge_controller,
  ecto_repos: [HiveforgeController.Repo]
