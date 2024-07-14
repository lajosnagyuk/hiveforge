defmodule HiveforgeController.JWTAuth do
  use Joken.Config
  require Logger

  @jwt_secret_key :jwt_secret

  @impl true
  def token_config do
    Logger.info("Configuring token claims")

    default_claims(default_exp: 60 * 60)
    |> add_claim("typ", fn -> "access" end, &(&1 == "access"))
  end

  def generate_token(api_key) do
    Logger.info("Generating token for api_key: #{inspect(api_key)}")

    extra_claims = %{
      "kid" => api_key.key_hash,
      "type" => api_key.type
    }

    signer = Joken.Signer.create("HS256", get_jwt_secret())

    case generate_and_sign(extra_claims, signer) do
      {:ok, token, claims} ->
        Logger.info("Token generated successfully. Claims: #{inspect(claims)}")
        token

      {:error, reason} ->
        Logger.error("Failed to generate token: #{inspect(reason)}")
        raise "Token generation failed"
    end
  end

  def verify_token(token) do
    Logger.info("Verifying token: #{token}")
    signer = Joken.Signer.create("HS256", get_jwt_secret())

    case verify_and_validate(token, signer) do
      {:ok, claims} ->
        Logger.info("Token verified successfully. Claims: #{inspect(claims)}")
        {:ok, claims}

      {:error, reason} ->
        Logger.error("Token verification failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_jwt_secret do
    case :persistent_term.get(@jwt_secret_key, :not_found) do
      :not_found ->
        Logger.info("JWT secret not found in persistent_term, fetching...")
        secret = fetch_jwt_secret()
        :persistent_term.put(@jwt_secret_key, secret)
        Logger.info("JWT secret stored in persistent_term")
        secret

      secret ->
        Logger.info("JWT secret retrieved from persistent_term")
        secret
    end
  end

  defp fetch_jwt_secret do
    case Application.fetch_env(:hiveforge_controller, __MODULE__) do
      {:ok, config} ->
        case Keyword.get(config, :secret_key) do
          nil ->
            Logger.error("JWT secret key is not configured in application environment")
            raise "JWT secret key is not configured"

          secret ->
            Logger.info("JWT secret fetched from application environment")
            secret
        end

      :error ->
        Logger.error(
          "HiveforgeController.JWTAuth configuration not found in application environment"
        )

        raise "HiveforgeController.JWTAuth configuration not found"
    end
  end

  def init_jwt_secret do
    Logger.info("Initializing JWT secret")
    secret = fetch_jwt_secret()
    :persistent_term.put(@jwt_secret_key, secret)
    Logger.info("JWT secret initialized and stored in persistent_term")
  end
end
