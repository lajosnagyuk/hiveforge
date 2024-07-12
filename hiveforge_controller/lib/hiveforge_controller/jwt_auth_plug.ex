defmodule HiveforgeController.JWTAuthPlug do
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- HiveforgeController.JWTAuth.verify_token(token) do
      assign(conn, :current_user, claims)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Invalid or missing token"}))
        |> halt()
    end
  end
end
