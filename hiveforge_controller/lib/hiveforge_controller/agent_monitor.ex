defmodule HiveforgeController.AgentMonitor do
  use GenServer
  alias HiveforgeController.{Agent, Repo}
  import Ecto.Query
  require Logger

  @check_interval 60_000 # 1 minute
  @missing_threshold 120 # 2 minutes

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check_agents, state) do
    check_missing_agents()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_agents, @check_interval)
  end

  defp check_missing_agents do
    threshold = DateTime.utc_now() |> DateTime.add(-@missing_threshold, :second)

    query = from a in Agent,
      where: (is_nil(a.last_heartbeat) and a.inserted_at < ^threshold) or
             (not is_nil(a.last_heartbeat) and a.last_heartbeat < ^threshold),
      where: a.status == "active"

    {count, _} = Repo.update_all(query, set: [status: "missing"])

    Logger.info("Marked #{count} agents as missing")
  end
end
