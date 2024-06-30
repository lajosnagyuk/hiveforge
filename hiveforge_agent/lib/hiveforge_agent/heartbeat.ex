defmodule HiveforgeAgent.Heartbeat do
  use GenServer
  require Logger

  @env_vars [:agent_id, :api_endpoint, :ca_cert_path]

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def send_heartbeat do
    GenServer.cast(__MODULE__, :send_heartbeat)
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    env_map =
      @env_vars
      |> Enum.map(fn key -> {key, get_env_var(key)} end)
      |> Enum.into(%{})

    :persistent_term.put(__MODULE__, env_map)

    case register_agent(env_map) do
      :ok ->
        Logger.info("Agent registered successfully")
        {:ok, env_map}
      {:error, reason} ->
        Logger.error("Failed to register agent: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast(:send_heartbeat, state) do
    do_send_heartbeat(state)
    {:noreply, state}
  end

  # Private functions

  defp do_send_heartbeat(env) do
    Logger.info("Sending heartbeat...")
    case env.api_endpoint do
      nil ->
        Logger.error("HIVEFORGE_CONTROLLER_API_ENDPOINT is not set")
      api_endpoint ->
        Logger.debug("API Endpoint: #{inspect(api_endpoint)}")
        Logger.debug("CA Cert Path: #{inspect(env.ca_cert_path)}")
        Logger.debug("Agent ID: #{inspect(env.agent_id)}")
        ca_cert_opts = get_ca_cert_opts(env.ca_cert_path)
        url = build_heartbeat_url(api_endpoint)
        Logger.info("Sending heartbeat to: #{url}")
        send_heartbeat_request(url, env.agent_id, ca_cert_opts)
    end
  end

  defp register_agent(env) do
    url = "#{env.api_endpoint}/api/v1/agents/register"
    body = Jason.encode!(%{
      name: "Agent-#{env.agent_id}",
      agent_id: env.agent_id,
      capabilities: get_agent_capabilities(),
      status: "active"
    })
    headers = [{"Content-Type", "application/json"}]
    ca_cert_opts = get_ca_cert_opts(env.ca_cert_path)

    case HTTPoison.post(url, body, headers, ca_cert_opts) do
      {:ok, %HTTPoison.Response{status_code: 201, body: response_body}} ->
        Logger.info("Agent registered successfully")
        :ok
      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.error("Agent registration failed. Status code: #{status_code}, Body: #{response_body}")
        {:error, :registration_failed}
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Agent registration request failed: #{inspect(reason)}")
        {:error, :request_failed}
    end
  end

  defp get_agent_capabilities do
    # Define or retrieve agent capabilities here
    # placeholder until I can get and define capabilities
    ["capability1", "capability2"]
  end

  defp get_env_var(:agent_id), do: System.get_env("HIVEFORGE_AGENT_ID")
  defp get_env_var(:api_endpoint), do: System.get_env("HIVEFORGE_CONTROLLER_API_ENDPOINT")
  defp get_env_var(:ca_cert_path), do: System.get_env("HIVEFORGE_CA_CERT_PATH", "")

  defp get_ca_cert_opts(ca_cert_path) do
    if ca_cert_path != "" do
      [cacertfile: ca_cert_path]
    else
      []
    end
  end

  defp build_heartbeat_url(api_endpoint) do
    "#{api_endpoint}/api/v1/agents/heartbeat"
  end

  defp send_heartbeat_request(url, agent_id, ca_cert_opts) do
    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(%{agent_id: agent_id})

    case HTTPoison.post(url, body, headers, ca_cert_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        Logger.info("Heartbeat sent successfully")
        {:ok, Jason.decode!(response_body)}
      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.error("Heartbeat failed. Status code: #{status_code}, Body: #{response_body}")
        {:error, :heartbeat_failed}
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Heartbeat request failed: #{inspect(reason)}")
        {:error, :request_failed}
    end
  end
end
