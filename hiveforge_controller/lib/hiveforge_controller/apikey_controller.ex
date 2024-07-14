defmodule HiveforgeController.ApiKeyController do
  use Plug.Builder
  alias HiveforgeController.ApiKeyService
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)
    apply(__MODULE__, action, [conn, conn.params])
  end

  def generate_key(conn, params) do
    claims = conn.assigns[:current_user]

    case ApiKeyService.generate_api_key(claims, params) do
      {:ok, new_key, api_key} ->
        conn
        |> put_status(:created)
        |> json_response(%{
          key: new_key,
          key_id: api_key.key_hash,
          type: api_key.type,
          message: "API Key #{api_key.type} generated successfully"
        })

      {:error, :invalid_key_type} ->
        error_response(conn, :bad_request, "Invalid key type")

      {:error, :unauthorized_operator_key_generation} ->
        error_response(conn, :unauthorized, "Unauthorized to generate operator keys")

      {:error, :invalid_params, errors} ->
        error_response(conn, :unprocessable_entity, "Invalid parameters: #{inspect(errors)}")

      {:error, reason} ->
        Logger.error("Unexpected error in generate_key: #{inspect(reason)}")
        error_response(conn, :internal_server_error, "An unexpected error occurred")
    end
  end

  def list_keys(conn, _params) do
    claims = conn.assigns[:current_user]

    case ApiKeyService.list_api_keys(claims) do
      {:ok, api_keys} ->
        conn
        |> put_status(:ok)
        |> json_response(api_keys)

      {:error, :unauthorized} ->
        error_response(conn, :unauthorized, "Unauthorized to list API keys")

      {:error, reason} ->
        Logger.error("Unexpected error in list_keys: #{inspect(reason)}")
        error_response(conn, :internal_server_error, "An unexpected error occurred")
    end
  end

  def revoke_key(conn, %{"key_id" => key_id}) do
    claims = conn.assigns[:current_user]

    case ApiKeyService.revoke_api_key(key_id, claims) do
      {:ok, _revoked_key} ->
        conn
        |> put_status(:ok)
        |> json_response(%{message: "API Key revoked successfully"})

      {:error, :not_found} ->
        error_response(conn, :not_found, "API Key not found")

      {:error, :unauthorized} ->
        error_response(conn, :unauthorized, "Unauthorized to revoke API keys")

      {:error, :update_failed, errors} ->
        error_response(
          conn,
          :unprocessable_entity,
          "Failed to revoke API key: #{inspect(errors)}"
        )

      {:error, reason} ->
        Logger.error("Unexpected error in revoke_key: #{inspect(reason)}")
        error_response(conn, :internal_server_error, "An unexpected error occurred")
    end
  end

  defp json_response(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(conn.status || 200, Jason.encode!(data))
  end

  defp error_response(conn, status, message) do
    conn
    |> put_status(status)
    |> json_response(%{error: message})
  end
end
