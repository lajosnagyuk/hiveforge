import Config

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
    verify: :verify_peer,
    cacertfile: System.get_env("POSTGRES_CACERTFILE"),
    server_name_indication: to_charlist(System.get_env("DB_HOST")),
    customize_hostname_check: [
      match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
    ]
  ]

config :hiveforge_controller,
  ecto_repos: [HiveforgeController.Repo]
