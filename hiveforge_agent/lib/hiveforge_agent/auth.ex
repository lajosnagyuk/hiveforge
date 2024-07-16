defmodule HiveforgeAgent.Auth do
  require Logger
  alias HTTPoison.Response

  @blake3_output_size 32  # 256 bits

  def authenticate(config) do
    Logger.info("Starting authentication process")
    api_endpoint = config.api_endpoint
    api_key = config.api_key

    # Step 1: Request a challenge
    challenge_url = "#{api_endpoint}/api/v1/auth/challenge"
    headers = [{"x-api-key-id", hash_key(api_key)}]

    Logger.debug("Requesting challenge from: #{challenge_url}")

    case HTTPoison.get(challenge_url, headers) do
      {:ok, %Response{status_code: 200, body: body}} ->
        {:ok, %{"challenge" => challenge}} = Jason.decode(body)
        Logger.debug("Received challenge: #{challenge}")
        verify_challenge(api_endpoint, api_key, challenge)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Failed to get challenge: #{inspect(reason)}")
        {:error, :challenge_request_failed}

      {:ok, %Response{status_code: status_code}} ->
        Logger.error("Failed to get challenge. Status code: #{status_code}")
        {:error, :challenge_request_failed}
    end
  end

  defp verify_challenge(api_endpoint, api_key, challenge) do
    Logger.info("Verifying challenge")
    verify_url = "#{api_endpoint}/api/v1/auth/verify"
    challenge_response = solve_challenge(challenge, api_key)
    headers = [
      {"x-api-key-id", hash_key(api_key)},
      {"Content-Type", "application/json"}
    ]
    body = Jason.encode!(%{challenge_response: challenge_response})

    Logger.debug("Sending challenge response to: #{verify_url}")

    case HTTPoison.post(verify_url, body, headers) do
      {:ok, %Response{status_code: 200, body: body}} ->
        {:ok, %{"token" => token}} = Jason.decode(body)
        Logger.info("Successfully verified challenge and received JWT")
        {:ok, token}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Failed to verify challenge: #{inspect(reason)}")
        {:error, :challenge_verification_failed}

      {:ok, %Response{status_code: status_code}} ->
        Logger.error("Failed to verify challenge. Status code: #{status_code}")
        {:error, :challenge_verification_failed}
    end
  end

  def hash_key(nil), do: nil
  def hash_key(key) do
    B3.hash(key)
    |> Base.encode64()
  end

  defp solve_challenge(challenge, key) do
    B3.hash(challenge <> key)
    |> Base.encode16(case: :lower)
  end


end
