import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id],
  level: :debug

config :logger, level: :debug

config :hiveforge_controller, HiveforgeController.Repo,
  username: System.get_env("DB_USERNAME"),
  password: System.get_env("DB_PASSWORD"),
  database: System.get_env("DB_NAME"),
  hostname: System.get_env("DB_HOST"),
  port: String.to_integer(System.get_env("DB_PORT") || "5432"),
  pool_size: 10,
  show_sensitive_data_on_connection_error: true,
  ssl: true,
  ssl_opts: [
    verify: :verify_none
  ]

config :hiveforge_controller, :enable_gzip_decompression, true

config :hiveforge_controller,
  ecto_repos: [HiveforgeController.Repo]

config :hiveforge_controller, HiveforgeController.AgentController,
  masterkey: System.get_env("HIVEFORGE_MASTER_KEY")

config :hiveforge_controller, HiveforgeController.JobController,
  masterkey: System.get_env("HIVEFORGE_MASTER_KEY")

config :hiveforge_controller, HiveforgeController.ApiKeyController,
  masterkey: System.get_env("HIVEFORGE_MASTER_KEY")

config :hiveforge_controller, HiveforgeController.JWTAuth,
  secret_key: System.get_env("HIVEFORGE_JWT_SECRET_KEY")
