defmodule HiveforgeController.ApiAuth do
  alias HiveforgeController.Repo
  alias HiveforgeController.ApiKey
  alias HiveforgeController.Common
  alias HiveforgeController.JWTAuth
  import Plug.Conn
  require Logger

  # API Key authentication for obtaining JWT

  def authenticate_api_key(conn) do
    api_key_hash = get_api_key_from_header(conn)
    get_api_key_by_hash(api_key_hash)
  end

  def get_api_key_by_hash(nil), do: {:error, "API key is missing"}

  def get_api_key_by_hash(hash) do
    case Repo.get_by(ApiKey, key_hash: hash) do
      nil ->
        Logger.warn("Authentication attempt with invalid API key hash: #{hash}")
        {:error, "Invalid API key"}

      api_key ->
        Logger.info("API Key authenticated - Type: #{api_key.type}, Hash: #{api_key.key_hash}")
        {:ok, api_key}
    end
  end

  defp get_api_key_from_header(conn) do
    get_req_header(conn, "x-api-key") |> List.first()
  end

  # JWT-related functions

  def generate_jwt(api_key) do
    JWTAuth.generate_token(api_key)
  end

  def verify_jwt(token) do
    JWTAuth.verify_token(token)
  end

  # JWT authentication and authorization

  def validate_jwt_request(conn, required_action) do
    Logger.debug("Validating JWT request for action: #{required_action}")

    with {:ok, token} <- get_jwt_from_header(conn),
         {:ok, claims} <- verify_jwt(token),
         auth_result when auth_result in [:ok, {:ok, :authorized}] <-
           authorize_action(claims, required_action) do
      Logger.debug("JWT request validated successfully")
      {:ok, claims}
    else
      {:error, reason} ->
        Logger.debug("JWT validation failed: #{reason}")
        {:error, reason}
    end
  end

  def get_jwt_from_header(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, "Missing or invalid Authorization header"}
    end
  end

  def authorize_action(claims, required_action) do
    Logger.debug("Authorizing action: #{required_action} for claims: #{inspect(claims)}")

    type = get_type(claims)

    result =
      case {type, required_action} do
        {"masterkey", _} ->
          :ok

        {"operator_key", _} ->
          :ok

        {_, :generate_operator_key} ->
          {:error, :unauthorized_operator_key_generation}

        {"agent_key", action} when action in [:register, :heartbeat, :get_job, :list_jobs] ->
          :ok

        {"reader_key", action} when action in [:list_agents, :get_agent, :get_job, :list_jobs] ->
          :ok

        _ ->
          {:error, "Unauthorized action for this key type"}
      end

    Logger.debug("Authorization result: #{inspect(result)}")
    result
  end

  defp get_type(%HiveforgeController.ApiKey{type: type}), do: type
  defp get_type(%{"type" => type}), do: type
  defp get_type(claims) when is_map(claims), do: Map.get(claims, "type")
  # Key generation (requires JWT)

  def generate_api_key(claims, params) do
    with {:ok, key_type} <- validate_key_type(params["type"]),
         {:ok, _} <- authorize_key_generation(claims, key_type),
         {new_key, key_hash} <- do_generate_api_key(),
         changeset <-
           ApiKey.changeset(%ApiKey{}, %{
             key_hash: key_hash,
             type: key_type,
             name: params["name"] || "Generated #{key_type}",
             description: params["description"] || "Generated with JWT",
             created_by: claims["type"]
           }),
         {:ok, api_key} <- Repo.insert(changeset) do
      Logger.info("New API Key generated - Type: #{key_type}, Hash: #{key_hash}")
      {:ok, new_key, api_key}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_generate_api_key do
    key = :crypto.strong_rand_bytes(32) |> Base.encode64()
    hash = Common.hash_key(key)
    {key, hash}
  end

  defp authorize_key_generation(claims, key_type) do
    case claims["type"] do
      "masterkey" -> {:ok, :authorized}
      "operator_key" -> {:ok, :authorized}
      _ when key_type == "operator_key" -> {:error, :unauthorized_operator_key_generation}
      _ -> {:error, :unauthorized_key_generation}
    end
  end

  def validate_key_type(type) when type in ["operator_key", "agent_key", "reader_key"] do
    {:ok, type}
  end

  def validate_key_type(_) do
    {:error, :invalid_key_type}
  end
end
