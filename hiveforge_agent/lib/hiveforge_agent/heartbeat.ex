defmodule HiveforgeAgent.Heartbeat do
  use GenServer
  require Logger
  alias HTTPoison.Response
  alias HiveforgeAgent.AgentIdentity

  @env_vars [:agent_id, :api_endpoint, :ca_cert_path]
  @retry_interval 5000  # 5 seconds
  @initial_delay 10000  # 10 seconds

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
    Logger.info("Initializing Heartbeat module")
    env_map =
      @env_vars
      |> Enum.map(fn key -> {key, get_env_var(key)} end)
      |> Enum.into(%{})

    Enum.each(env_map, fn {key, value} ->
      :persistent_term.put({__MODULE__, key}, value)
      Logger.debug("Set persistent term for #{key}: #{inspect(value)}")
    end)

    # Schedule a delayed registration attempt
    Process.send_after(self(), :try_register, @initial_delay)

    {:ok, %{registered: false}}
  end

  @impl true
  def handle_info(:try_register, state) do
    Logger.info("Attempting to register agent")
    case register_agent() do
      :ok ->
        Logger.info("Agent registered successfully")
        {:noreply, %{state | registered: true}}

      {:error, :jwt_not_available} ->
        Logger.warn("JWT not available yet, retrying in #{@retry_interval}ms")
        Process.send_after(self(), :try_register, @retry_interval)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to register agent: #{inspect(reason)}")
        Process.send_after(self(), :try_register, @retry_interval)
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:send_heartbeat, %{registered: true} = state) do
    Logger.info("Sending heartbeat")
    do_send_heartbeat()
    {:noreply, state}
  end

  def handle_cast(:send_heartbeat, state) do
    Logger.warn("Heartbeat requested but agent is not registered yet")
    {:noreply, state}
  end

  # Private functions
  defp do_send_heartbeat do
    case get_env(:api_endpoint) do
      nil ->
        Logger.error("HIVEFORGE_CONTROLLER_API_ENDPOINT is not set")

      api_endpoint ->
        Logger.debug("API Endpoint: #{inspect(api_endpoint)}")
        ca_cert_opts = get_ca_cert_opts(get_env(:ca_cert_path))
        url = build_heartbeat_url(api_endpoint)
        Logger.info("Sending heartbeat to: #{url}")
        send_heartbeat_request(url, get_env(:agent_id), ca_cert_opts)
    end
  end

  defp register_agent do
    url = "#{get_env(:api_endpoint)}/api/v1/agents/register"

    data = %{
      name: "Agent-#{get_env(:agent_id)}",
      agent_id: get_env(:agent_id),
      capabilities: get_agent_capabilities(),
      status: "active"
    }

    body = Jason.encode!(data)

    case AgentIdentity.get_jwt() do
      {:ok, jwt} ->
        headers = [
          {"Content-Type", "application/json"},
          {"Authorization", "Bearer #{jwt}"}
        ]
        send_registration_request(url, headers, body)

      {:error, :jwt_not_available} ->
        {:error, :jwt_not_available}

      jwt when is_binary(jwt) ->
        Logger.warn("Unexpected JWT format, using as-is")
        headers = [
          {"Content-Type", "application/json"},
          {"Authorization", "Bearer #{jwt}"}
        ]
        send_registration_request(url, headers, body)
    end
  end

  defp send_registration_request(url, headers, body) do
    ca_cert_opts = get_ca_cert_opts(get_env(:ca_cert_path))

    Logger.debug("Sending registration request to: #{url}")
    Logger.debug("Registration headers: #{inspect(headers)}")
    Logger.debug("Registration body: #{inspect(body)}")

    case HTTPoison.post(url, body, headers, ca_cert_opts) do
      {:ok, %Response{status_code: 201}} ->
        Logger.info("Agent registered successfully")
        :ok

      {:ok, %Response{status_code: 401}} ->
        Logger.warn("JWT expired, refreshing...")
        case AgentIdentity.refresh_jwt() do
          {:ok, _new_token} -> register_agent()
          {:error, reason} -> {:error, reason}
        end

      {:ok, %Response{status_code: status_code, body: response_body}} ->
        Logger.error(
          "Agent registration failed. Status code: #{status_code}, Body: #{response_body}"
        )
        {:error, :registration_failed}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Agent registration request failed: #{inspect(reason)}")
        {:error, :request_failed}
    end
  end

  defp send_heartbeat_request(url, agent_id, ca_cert_opts) do
    case AgentIdentity.get_jwt() do
      {:ok, jwt} ->
        headers = [
          {"Content-Type", "application/json"},
          {"Authorization", "Bearer #{jwt}"}
        ]
        do_send_heartbeat_request(url, headers, agent_id, ca_cert_opts)

      {:error, :jwt_not_available} ->
        Logger.error("JWT not available for heartbeat")
        {:error, :jwt_not_available}

      jwt when is_binary(jwt) ->
        Logger.warn("Unexpected JWT format, using as-is")
        headers = [
          {"Content-Type", "application/json"},
          {"Authorization", "Bearer #{jwt}"}
        ]
        do_send_heartbeat_request(url, headers, agent_id, ca_cert_opts)
    end
  end

  defp do_send_heartbeat_request(url, headers, agent_id, ca_cert_opts) do
    body = Jason.encode!(%{agent_id: agent_id})

    Logger.debug("Sending heartbeat request to: #{url}")
    Logger.debug("Heartbeat headers: #{inspect(headers)}")
    Logger.debug("Heartbeat body: #{inspect(body)}")

    case HTTPoison.post(url, body, headers, ca_cert_opts) do
      {:ok, %Response{status_code: 200, body: response_body}} ->
        Logger.info("Heartbeat sent successfully")
        {:ok, Jason.decode!(response_body)}

      {:ok, %Response{status_code: 401}} ->
        Logger.warn("JWT expired, refreshing...")
        case AgentIdentity.refresh_jwt() do
          {:ok, _new_token} -> send_heartbeat_request(url, agent_id, ca_cert_opts)
          {:error, reason} -> {:error, reason}
        end

      {:ok, %Response{status_code: status_code, body: response_body}} ->
        Logger.error("Heartbeat failed. Status code: #{status_code}, Body: #{response_body}")
        {:error, :heartbeat_failed}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Heartbeat request failed: #{inspect(reason)}")
        {:error, :request_failed}
    end
  end

  defp get_agent_capabilities do
    ["capability1", "capability2"]
  end

  defp get_env(key) do
    :persistent_term.get({__MODULE__, key})
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
end
