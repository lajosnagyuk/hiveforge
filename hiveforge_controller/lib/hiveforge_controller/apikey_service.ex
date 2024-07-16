defmodule HiveforgeController.ApiKeyService do
  alias HiveforgeController.{Repo, ApiKey, Common}
  import Ecto.Query
  require Logger

  def generate_api_key(claims, params) do
    with {:ok, key_type} <- validate_key_type(params["type"]),
         :ok <- authorize_key_generation(claims, key_type),
         {new_key, key_hash} <- do_generate_api_key(),
         api_key_attrs <- %{
           key: new_key,
           key_hash: key_hash,
           type: key_type,
           name: params["name"] || "Generated #{key_type}",
           description: params["description"] || "Generated with JWT",
           expires_at: parse_expiration(params["expires_at"]),
           created_by: claims["sub"]
         },
         changeset <- ApiKey.changeset(%ApiKey{}, api_key_attrs),
         {:ok, api_key} <- Repo.insert(changeset) do
      Logger.info("New API Key generated - Type: #{key_type}, Hash: #{key_hash}")
      {:ok, new_key, api_key}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, :invalid_params, changeset.errors}
      {:error, reason} -> {:error, reason}
    end
  end

  def list_api_keys(claims) do
    case authorize_list_keys(claims) do
      :ok ->
        api_keys =
          ApiKey
          |> where([k], is_nil(k.revoked_at))
          |> order_by([k], desc: k.inserted_at)
          |> Repo.all()

        {:ok, api_keys}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def revoke_api_key(key_id, claims) do
    case authorize_revoke_key(claims) do
      :ok ->
        api_key = Repo.get_by(ApiKey, key_hash: key_id)

        if api_key do
          changeset = ApiKey.changeset(api_key, %{revoked_at: DateTime.utc_now()})

          case Repo.update(changeset) do
            {:ok, updated_key} -> {:ok, updated_key}
            {:error, changeset} -> {:error, :update_failed, changeset.errors}
          end
        else
          {:error, :not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def authenticate_api_key(api_key_hash) do
    case get_api_key_by_hash(api_key_hash) do
      {:ok, api_key} ->
        Logger.info("API Key authenticated - Type: #{api_key.type}, Hash: #{api_key.key_hash}")
        {:ok, api_key}

      error ->
        error
    end
  end

  def get_api_key_by_hash(nil), do: {:error, "API key is missing"}

  def get_api_key_by_hash(hash) do
    query = from(a in ApiKey, where: a.key_hash == ^hash, select: [:id, :key, :key_hash, :type, :name])
    case Repo.one(query) do
      nil ->
        Logger.warn("Authentication attempt with invalid API key hash: #{hash}")
        {:error, "Invalid API key"}

      api_key ->
        Logger.debug("API Key found: #{inspect(api_key, pretty: true)}")
        {:ok, api_key}
    end
  end

  def verify_api_key(api_key, provided_key) do
    case Common.verify_key(provided_key, api_key.key) do
      true -> {:ok, api_key}
      false -> {:error, "Invalid API key"}
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

        {"agent_key", action} when action in [:register_agent, :update_heartbeat, :get_job, :list_jobs, :request_challenge, :verify_challenge] ->
          :ok

        {"reader_key", action} when action in [:list_agents, :get_agent, :get_job, :list_jobs, :request_challenge, :verify_challenge] ->
          :ok

        _ ->
          {:error, "Unauthorized action for this key type"}
      end

    Logger.debug("Authorization result: #{inspect(result)}")
    result
  end

  # Helper functions

  defp do_generate_api_key do
    # Generate a 32-character key
    key = generate_user_friendly_key(32)
    hash = Common.hash_key(key)
    {key, hash}
  end

  defp generate_user_friendly_key(length) do
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    alphabet_length = String.length(alphabet)

    1..length
    |> Enum.map(fn _ ->
      :crypto.strong_rand_bytes(1)
      |> :binary.first()
      |> rem(alphabet_length)
      |> (fn index -> String.at(alphabet, index) end).()
    end)
    |> Enum.join()
  end

  defp authorize_key_generation(%{"type" => "masterkey"}, _), do: :ok
  defp authorize_key_generation(%{"type" => "operator_key"}, _), do: :ok

  defp authorize_key_generation(_, "operator_key"),
    do: {:error, :unauthorized_operator_key_generation}

  defp authorize_key_generation(_, _), do: :ok

  defp authorize_list_keys(%{"type" => type}) when type in ["masterkey", "operator_key"], do: :ok
  defp authorize_list_keys(_), do: {:error, :unauthorized}

  defp authorize_revoke_key(%{"type" => type}) when type in ["masterkey", "operator_key"], do: :ok
  defp authorize_revoke_key(_), do: {:error, :unauthorized}

  defp validate_key_type(type) when type in ["operator_key", "agent_key", "reader_key"],
    do: {:ok, type}

  defp validate_key_type(_), do: {:error, :invalid_key_type}

  defp get_type(%HiveforgeController.ApiKey{type: type}), do: type
  defp get_type(%{"type" => type}), do: type
  defp get_type(claims) when is_map(claims), do: Map.get(claims, "type")

  defp parse_expiration(nil), do: nil

  defp parse_expiration(expiration_string) do
    case DateTime.from_iso8601(expiration_string) do
      {:ok, datetime, _} -> datetime
      {:error, _} -> nil
    end
  end
end
