defmodule HiveforgeController.ApiAuth do
  require Logger
  alias HiveforgeController.{Repo, ApiKey, Agent}

  def generate_api_key(_type) do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  def validate_request(conn, params) do
    with {:ok, auth_key} <- get_auth_key(conn),
         :ok <- validate_signature(auth_key, conn, params) do
      {:ok, auth_key}
    end
  end

  def get_auth_key(conn) do
    case Plug.Conn.get_req_header(conn, "x-api-key") do
      [key | _] ->
        case Repo.get_by(ApiKey, key: key) do
          nil -> {:error, "Invalid API key"}
          api_key -> {:ok, api_key}
        end

      [] ->
        {:error, "Missing API key"}
    end
  end

  def validate_signature(auth_key, conn, params) do
    nonce = Plug.Conn.get_req_header(conn, "x-nonce") |> List.first()
    signature = Plug.Conn.get_req_header(conn, "x-signature") |> List.first()

    case {nonce, signature} do
      {nil, _} ->
        {:error, "Missing nonce"}

      {_, nil} ->
        {:error, "Missing signature"}

      {nonce, signature} ->
        expected_signature = generate_signature(auth_key.key, nonce, params)
        if expected_signature == signature, do: :ok, else: {:error, "Invalid signature"}
    end
  end

  defp generate_signature(key, nonce, params) do
    transaction_key = :crypto.mac(:hmac, :sha256, key, "TRANSACTION" <> nonce)

    :crypto.mac(:hmac, :sha256, transaction_key, Jason.encode!(params))
    |> Base.encode64()
  end

  def validate_master_key(provided_key) do
    master_key = Application.get_env(:hiveforge_controller, :master_key)
    provided_key == master_key
  end

  defp get_agent_key(agent_id) do
    Logger.debug("Getting agent key for agent_id: #{inspect(agent_id)}")

    case Repo.get_by(Agent, agent_id: agent_id) do
      nil ->
        Logger.warn("Agent not found for agent_id: #{inspect(agent_id)}")
        nil

      agent ->
        Logger.debug("Agent found: #{inspect(agent)}")
        agent.agent_key
    end
  end
end
