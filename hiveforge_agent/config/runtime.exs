import Config

config :hiveforge_agent, HiveforgeAgent.Queryjobs,
  hiveforge_controller_api_endpoint: System.get_env("HIVEFORGE_CONTROLLER_API_ENDPOINT"),
  ca_cert_path: System.get_env("HIVEFORGE_CA_CERT_PATH", "")

config :hiveforge_agent, HiveforgeAgent.Scheduler,
  jobs: [
    {{:extended, "*/10 * * * * *"}, {HiveforgeAgent.Queryjobs, :queryActiveJobs, []}},
    {{:extended, "*/20 * * * * *"}, {HiveforgeAgent.Heartbeat, :send_heartbeat, []}}
  ]
