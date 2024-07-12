defmodule HiveforgeController.ApiAuth do
  alias HiveforgeController.Repo
  alias HiveforgeController.ApiKey
  alias HiveforgeController.Common
  import Plug.Conn
  require Logger

  def get_authenticated_api_key(nil), do: {:error, "API key is missing"}
  def get_authenticated_api_key(api_key_hash) do
    case Repo.get_by(ApiKey, key_hash: api_key_hash) do
      nil ->
        Logger.warn("Authentication attempt with invalid API key hash: #{api_key_hash}")
        {:error, "Invalid API key"}
      api_key ->
        Logger.info("API Key authenticated - Type: #{api_key.type}, Hash: #{api_key.key_hash}")
        {:ok, api_key}
    end
  end

  def validate_request(conn, _params, required_action) do
    with {:ok, auth_key} <- get_authenticated_api_key(get_api_key_from_header(conn)),
         :ok <- authorize_action(auth_key, required_action) do
      {:ok, auth_key}
    end
  end

  def get_api_key_from_header(conn) do
    get_req_header(conn, "authorization")
    |> List.first()
  end

  def authorize_action(%{type: "operator_key"}, _action), do: :ok
  def authorize_action(%{type: "agent_key"}, action) when action in [:register, :heartbeat, :request_challenge, :verify_challenge], do: :ok
  def authorize_action(%{type: "reader_key"}, action) when action in [:list_agents, :get_agent, :request_challenge, :verify_challenge, :get_job, :list_jobs], do: :ok
  def authorize_action(_, _), do: {:error, "Unauthorized action for this key type"}

  def get_api_key_by_hash(hash) do
    case Repo.get_by(ApiKey, key_hash: hash) do
      nil -> {:error, "Invalid API key"}
      api_key -> {:ok, api_key}
    end
  end

  def generate_api_key do
    {key, hash} = do_generate_api_key()
    Logger.info("New API Key generated - Hash: #{hash}")
    {key, hash}
  end

  defp do_generate_api_key do
    key = :crypto.strong_rand_bytes(32) |> Base.encode64
    hash = Common.hash_key(key)
    {key, hash}
  end

  def verify_challenge_response(challenge, response, key_hash) do
    expected_response = Common.hash_key(challenge <> key_hash)
    if response == expected_response do
      :ok
    else
      {:error, "Invalid challenge response"}
    end
  end
end
