defmodule HiveforgeAgent.Heartbeat do
  use GenServer
  require Logger
  alias HTTPoison.Response

  @env_vars [:agent_id, :api_endpoint, :ca_cert_path, :agent_key]

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

    Enum.each(env_map, fn {key, value} ->
      :persistent_term.put({__MODULE__, key}, value)
    end)

    case register_agent() do
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
  defp do_send_heartbeat(_env) do
    Logger.info("Sending heartbeat...")

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
    {nonce, signature} = sign_request(body)

    headers = [
      {"Content-Type", "application/json"},
      {"X-Agent-ID", get_env(:agent_id)},
      {"X-Nonce", nonce},
      {"X-Signature", signature}
    ]

    ca_cert_opts = get_ca_cert_opts(get_env(:ca_cert_path))

    case HTTPoison.post(url, body, headers, ca_cert_opts) do
      {:ok, %Response{status_code: 201, body: response_body}} ->
        Logger.info("Agent registered successfully")
        :ok

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

  defp get_agent_capabilities do
    # Define or retrieve agent capabilities here
    # placeholder until you can get and define capabilities
    ["capability1", "capability2"]
  end

  defp get_env(key) do
    :persistent_term.get({__MODULE__, key})
  end

  defp get_env_var(:agent_id), do: System.get_env("HIVEFORGE_AGENT_ID")
  defp get_env_var(:api_endpoint), do: System.get_env("HIVEFORGE_CONTROLLER_API_ENDPOINT")
  defp get_env_var(:ca_cert_path), do: System.get_env("HIVEFORGE_CA_CERT_PATH", "")
  defp get_env_var(:agent_key), do: System.get_env("HIVEFORGE_AGENT_KEY")

  defp get_ca_cert_opts(ca_cert_path) do
    if ca_cert_path != "" do
      [cacertfile: ca_cert_path]
    else
      []
    end
  end

  defp sign_request(data) do
    nonce = generate_nonce()
    transaction_key = generate_transaction_key(nonce)
    signature = :crypto.mac(:hmac, :sha256, transaction_key, data) |> Base.encode64()

    Logger.debug("Nonce: #{inspect(nonce)}")
    Logger.debug("Transaction Key: #{Base.encode64(transaction_key)}")
    Logger.debug("Signature: #{inspect(signature)}")

    {nonce, signature}
  end

  defp generate_nonce do
    :crypto.strong_rand_bytes(16) |> Base.encode64()
  end

  defp generate_transaction_key(nonce) do
    agent_key = get_env(:agent_key)
    :crypto.mac(:hmac, :sha256, agent_key, "TRANSACTION" <> nonce)
  end

  defp build_heartbeat_url(api_endpoint) do
    "#{api_endpoint}/api/v1/agents/heartbeat"
  end

  defp send_heartbeat_request(url, agent_id, ca_cert_opts) do
    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(%{agent_id: agent_id})

    Logger.debug("Sending request to: #{url}")
    Logger.debug("Request body: #{inspect(body)}")
    Logger.debug("Headers: #{inspect(headers)}")

    case HTTPoison.post(url, body, headers, ca_cert_opts) do
      {:ok, %Response{status_code: 200, body: response_body}} ->
        Logger.info("Heartbeat sent successfully")
        {:ok, Jason.decode!(response_body)}

      {:ok, %Response{status_code: status_code, body: response_body}} ->
        Logger.error("Heartbeat failed. Status code: #{status_code}, Body: #{response_body}")
        {:error, :heartbeat_failed}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Heartbeat request failed: #{inspect(reason)}")
        {:error, :request_failed}
    end
  end
end
