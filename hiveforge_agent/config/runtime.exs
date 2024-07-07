import Config

config :hiveforge_agent, HiveforgeAgent.Queryjobs,
  hiveforge_controller_api_endpoint: System.get_env("HIVEFORGE_CONTROLLER_API_ENDPOINT"),
  ca_cert_path: System.get_env("HIVEFORGE_CA_CERT_PATH", "")

config :hiveforge_agent, HiveforgeAgent.Scheduler,
  jobs: [
    {{:extended, "*/10 * * * *"}, {HiveforgeAgent.Queryjobs, :queryActiveJobs, []}},
    {{:extended, "*/20 * * * *"}, {HiveforgeAgent.Heartbeat, :send_heartbeat, []}}
  ]

# Configurations for agent identification and key
config :hiveforge_agent, HiveforgeAgent.AgentIdentity,
  agent_id: System.get_env("HIVEFORGE_AGENT_ID"),
  agent_key: System.get_env("HIVEFORGE_AGENT_KEY")

# If you want to use these in persistent_term, you can add a configuration like this:
config :hiveforge_agent, :persistent_term_keys, [
  :hiveforge_controller_api_endpoint,
  :ca_cert_path,
  :agent_id,
  :agent_key
]
