defmodule HiveforgeController.AuthController do
  use Plug.Builder
  alias HiveforgeController.{ApiAuth, Common, JWTAuth}
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)
    apply(__MODULE__, action, [conn, conn.params])
  end

  def request_challenge(conn, _params) do
      api_key_id = get_req_header(conn, "x-api-key-id") |> List.first()

      Logger.debug("Received request for challenge")
      Logger.debug("API Key ID: #{inspect(api_key_id)}")
      Logger.debug("All headers: #{inspect(conn.req_headers)}")

      config = Application.get_env(:hiveforge_controller, HiveforgeController.ApiKeyController)
      master_key_hash = Common.hash_key(config[:masterkey])

      Logger.debug("Master Key Hash: #{inspect(master_key_hash)}")

      cond do
        master_key_hash == api_key_id ->
          Logger.debug("Matched with Master Key")
          challenge = generate_challenge()
          store_challenge(api_key_id, challenge)
          json_response(conn, 200, %{challenge: challenge})
        true ->
          Logger.debug("Attempting to match with API Key")
          case ApiAuth.get_api_key_by_hash(api_key_id) do
            {:ok, api_key} ->
              case ApiAuth.authorize_action(api_key, :request_challenge) do
                :ok ->
                  challenge = generate_challenge()
                  store_challenge(api_key_id, challenge)
                  json_response(conn, 200, %{challenge: challenge})
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

    config = Application.get_env(:hiveforge_controller, HiveforgeController.ApiKeyController)
    master_key_hash = Common.hash_key(config[:masterkey])

    try do
      cond do
        master_key_hash == api_key_id ->
          Logger.debug("Verifying Master Key challenge")
          if verify_challenge_response(stored_challenge, challenge_response, config[:masterkey]) do
            token = JWTAuth.generate_token(%{type: "masterkey", key_hash: master_key_hash})
            json_response(conn, 200, %{token: token})
          else
            Logger.debug("Invalid challenge response for Master Key")
            json_response(conn, 401, %{error: "Invalid challenge response"})
          end
        true ->
          Logger.debug("Verifying API Key challenge")
          with {:ok, api_key} <- ApiAuth.get_api_key_by_hash(api_key_id),
               :ok <- ApiAuth.authorize_action(%{"type" => api_key.type}, :verify_challenge),
               true <- verify_challenge_response(stored_challenge, challenge_response, api_key.key_hash),
               token <- JWTAuth.generate_token(api_key) do
            json_response(conn, 200, %{token: token})
          else
            false ->
              Logger.debug("Invalid challenge response for API Key")
              json_response(conn, 401, %{error: "Invalid challenge response"})
            {:error, reason} ->
              Logger.debug("Error verifying API Key challenge: #{inspect(reason)}")
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

  defp verify_challenge_response(challenge, response, key) do
    Logger.debug("Verifying challenge response")
    Logger.debug("Challenge: #{inspect(challenge)}")
    Logger.debug("Response: #{inspect(response)}")
    Logger.debug("Key (first 8 chars): #{String.slice(key, 0, 8)}")

    expected_response = Common.hash_key(challenge <> key)
    Logger.debug("Expected Response: #{inspect(expected_response)}")

    result = response == expected_response
    Logger.debug("Verification result: #{result}")

    result
  end

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
