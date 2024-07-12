defmodule HiveforgeController.JWTAuth do
  use Joken.Config

  @impl true
  def token_config do
    default_claims(default_exp: 60 * 60) # 1 hour expiration
    |> add_claim("typ", fn -> "access" end, &(&1 == "access"))
  end

  def generate_token(api_key) do
    extra_claims = %{
      "kid" => api_key.key_hash,
      "type" => api_key.type
    }
    signer = Joken.Signer.create("HS256", get_jwt_secret())
    {:ok, token, _claims} = generate_and_sign(extra_claims, signer)
    token
  end

  def verify_token(token) do
    signer = Joken.Signer.create("HS256", get_jwt_secret())
    case verify_and_validate(token, signer) do
      {:ok, claims} -> {:ok, claims}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_jwt_secret do
    Application.get_env(:hiveforge_controller, __MODULE__)[:secret_key] ||
      raise "JWT secret key is not configured"
  end
end
