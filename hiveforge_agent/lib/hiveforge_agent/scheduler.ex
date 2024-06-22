defmodule HiveforgeAgent.Scheduler do
  use Quantum, otp_app: :hiveforge_agent
  require Logger

  def init(config) do
    Logger.debug("Initializing Scheduler with config: #{inspect(config)}")
    super(config)
  rescue
    e ->
      Logger.error("Scheduler failed to initialize: #{inspect(e)}")
      raise e
  end
end
