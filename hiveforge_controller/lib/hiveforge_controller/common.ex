defmodule HiveforgeController.Common do
  require Logger


  @blake3_output_size 32  # 256 bits

  def hash_key(nil), do: nil
  def hash_key(key) do
    B3.hash(key)
    |> Base.encode64()
  end

  def verify_key(key, key_hash) do
    key_hash == hash_key(key)
  end

  def verify_challenge_response(challenge, response, key) do
    Logger.debug("Verifying challenge response")
    Logger.debug("Challenge: #{inspect(challenge)}")
    Logger.debug("Response: #{inspect(response)}")
    Logger.debug("Key (first 8 chars or nil): #{if key, do: String.slice(key, 0, 8), else: "nil"}")

    cond do
      is_nil(challenge) ->
        Logger.error("Challenge is nil in verify_challenge_response")
        false
      is_nil(response) ->
        Logger.error("Response is nil in verify_challenge_response")
        false
      is_nil(key) ->
        Logger.error("Key is nil in verify_challenge_response")
        false
      true ->
        expected_response = B3.hash(challenge <> key) |> Base.encode16(case: :lower)
        Logger.debug("Expected Response: #{inspect(expected_response)}")

        result = Plug.Crypto.secure_compare(response, expected_response)
        Logger.debug("Verification result: #{result}")

        result
    end
  end
end
