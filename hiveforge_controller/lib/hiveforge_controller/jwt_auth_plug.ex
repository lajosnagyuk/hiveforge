defmodule HiveforgeController.JWTAuthPlug do
  import Plug.Conn
  require Logger

  def init(opts) do
    Logger.info("Initializing JWTAuthPlug")
    opts
  end

  def call(conn, _opts) do
    Logger.info("JWTAuthPlug called")
    headers = conn.req_headers |> Enum.map(fn {k, v} -> "#{k}: #{v}" end) |> Enum.join("\n")
    Logger.info("Headers in JWTAuthPlug:\n#{headers}")

    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        Logger.info("Bearer token found in Authorization header")

        case HiveforgeController.JWTAuth.verify_token(token) do
          {:ok, claims} ->
            Logger.info("Token verified successfully. Claims: #{inspect(claims)}")
            assign(conn, :current_user, claims)

          {:error, reason} ->
            Logger.error("Token verification failed: #{inspect(reason)}")
            send_unauthorized_response(conn, "Invalid token")
        end

      [] ->
        Logger.error("No Authorization header found")
        send_unauthorized_response(conn, "Missing token")

      _other ->
        Logger.error("Malformed Authorization header")
        send_unauthorized_response(conn, "Invalid Authorization header format")
    end
  end

  defp send_unauthorized_response(conn, error_message) do
    Logger.info("Sending unauthorized response: #{error_message}")

    conn
    |> put_status(:unauthorized)
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "Invalid or missing token"}))
    |> halt()
  end
end
