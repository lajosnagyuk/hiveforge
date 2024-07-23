defmodule HiveforgeController.JWTAuthPlug do
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    Logger.info("JWTAuthPlug called")
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        Logger.info("Bearer token found in Authorization header")
        case HiveforgeController.JWTAuth.verify_token(token) do
          {:ok, claims} ->
            Logger.info("Token verified successfully. Claims: #{inspect(claims)}")
            assign(conn, :current_user, claims)
          {:error, reason} ->
            Logger.error("Token verification failed: #{inspect(reason)}")
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Invalid token"})
            |> halt()
        end
      _ ->
        Logger.error("No valid Authorization header found")
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Missing or invalid Authorization header"})
        |> halt()
    end
  end

  defp json(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(conn.status, Jason.encode!(data))
  end
end
