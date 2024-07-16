defmodule HiveforgeController.AuthController do
  use Plug.Builder
  alias HiveforgeController.{ApiKeyService, Common, JWTAuth}
  import Plug.Conn
  require Logger

  @master_key_term :hiveforge_master_key

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)
    apply(__MODULE__, action, [conn, conn.params])
  end

  def request_challenge(conn, _params) do
    api_key_id = get_req_header(conn, "x-api-key-id") |> List.first()
    Logger.debug("Received request for challenge")
    Logger.debug("API Key ID: #{inspect(api_key_id)}")

    master_key = get_master_key()
    master_key_hash = Common.hash_key(master_key)

    Logger.debug("Master Key Hash: #{inspect(master_key_hash)}")

    cond do
      Common.verify_key(master_key, api_key_id) ->
        Logger.debug("Matched with Master Key")
        handle_challenge_request(conn, api_key_id)

      true ->
        Logger.debug("Attempting to match with API Key")

        case ApiKeyService.get_api_key_by_hash(api_key_id) do
          {:ok, api_key} ->
            case ApiKeyService.authorize_action(api_key, :request_challenge) do
              :ok ->
                handle_challenge_request(conn, api_key.key_hash)

              {:error, reason} ->
                Logger.debug("Authorization Error: #{inspect(reason)}")
                json_response(conn, 401, %{error: reason})
            end

          {:error, reason} ->
            Logger.debug("API Key Error: #{inspect(reason)}")
            json_response(conn, 401, %{error: reason})
        end
    end
  end

  defp handle_challenge_request(conn, key_hash) do
    challenge = generate_challenge()
    store_challenge(key_hash, challenge)
    json_response(conn, 200, %{challenge: challenge})
  end

  defp store_challenge(api_key_id, challenge) do
    :ets.insert(HiveforgeController.SessionStore.table_name(), {api_key_id, challenge})
  end

  defp get_stored_challenge(api_key_id) do
    case :ets.lookup(HiveforgeController.SessionStore.table_name(), api_key_id) do
      [{^api_key_id, challenge}] -> challenge
      [] -> nil
    end
  end

  defp generate_challenge do
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end

  def verify_challenge(conn, params) do
    api_key_id = get_req_header(conn, "x-api-key-id") |> List.first()
    challenge_response = params["challenge_response"]

    Logger.debug("Verifying challenge")
    Logger.debug("API Key ID: #{inspect(api_key_id)}")
    Logger.debug("Params: #{inspect(params)}")
    Logger.debug("Headers: #{inspect(conn.req_headers)}")
    Logger.debug("Challenge Response: #{inspect(challenge_response)}")

    stored_challenge = get_stored_challenge(api_key_id)
    Logger.debug("Stored Challenge: #{inspect(stored_challenge)}")

    master_key = get_master_key()
    master_key_hash = Common.hash_key(master_key)

    Logger.debug("Master Key Hash: #{inspect(master_key_hash)}")

    try do
      cond do
        master_key_hash == api_key_id ->
          Logger.debug("Verifying Master Key challenge")

          if Common.verify_challenge_response(stored_challenge, challenge_response, master_key) do
            token = JWTAuth.generate_token(%{type: "masterkey", key_hash: master_key_hash})
            json_response(conn, 200, %{token: token})
          else
            Logger.debug("Invalid challenge response for Master Key")
            json_response(conn, 401, %{error: "Invalid challenge response"})
          end

        true ->
          Logger.debug("Verifying API Key challenge")

          case ApiKeyService.get_api_key_by_hash(api_key_id) do
            {:ok, api_key} ->
              Logger.debug("API Key found: #{inspect(api_key, pretty: true)}")
              case ApiKeyService.authorize_action(%{"type" => api_key.type}, :verify_challenge) do
                :ok ->
                  Logger.debug("API Key authorized for challenge verification")
                  Logger.debug("Stored challenge: #{stored_challenge}")
                  Logger.debug("Challenge response: #{challenge_response}")
                  Logger.debug("API Key: #{inspect(api_key, pretty: true)}")

                  if Common.verify_challenge_response(stored_challenge, challenge_response, api_key.key) do
                    token = JWTAuth.generate_token(api_key)
                    json_response(conn, 200, %{token: token})
                  else
                    Logger.debug("Invalid challenge response for API Key")
                    json_response(conn, 401, %{error: "Invalid challenge response"})
                  end

                {:error, reason} ->
                  Logger.debug("Error authorizing API Key challenge: #{inspect(reason)}")
                  json_response(conn, 401, %{error: reason})
              end

            {:error, reason} ->
              Logger.debug("Error retrieving API Key: #{inspect(reason)}")
              json_response(conn, 401, %{error: reason})
          end
      end
    rescue
      e ->
        Logger.error("Unexpected error during challenge verification: #{inspect(e)}")
        Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
        json_response(conn, 500, %{error: "Internal server error: #{inspect(e)}"})
    end
  end

  defp get_master_key do
    case :persistent_term.get(@master_key_term, :not_found) do
      :not_found ->
        Logger.warn("Master key not found in persistent term. Initializing...")
        init_master_key()
      key -> key
    end
  end

  def init_master_key do
    config = Application.get_env(:hiveforge_controller, HiveforgeController.ApiKeyController)
    case config[:masterkey] do
      nil ->
        Logger.error("Master key not found in configuration")
        raise "Master key is not configured"
      master_key ->
        :persistent_term.put(@master_key_term, master_key)
        Logger.info("Master key initialized in persistent term")
        master_key
    end
  end


  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
