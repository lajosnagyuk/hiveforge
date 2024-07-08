defmodule HiveforgeController.ApiKeyController do
  use Plug.Builder
  alias HiveforgeController.{ApiAuth, ApiKey, Repo, Common, JWTAuth}
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)
    apply(__MODULE__, action, [conn, conn.params])
  end

  def generate_key(conn, params) do
    config = Application.get_env(:hiveforge_controller, HiveforgeController.ApiKeyController)
    masterkey_hash = Common.hash_key(config[:masterkey])
    provided_key_hash = get_req_header(conn, "x-master-key-hash") |> List.first()
    api_key_hash = get_req_header(conn, "x-api-key-hash") |> List.first()

    Logger.debug("Master Key Hash: #{masterkey_hash}, Provided Key Hash: #{provided_key_hash}, API Key Hash: #{api_key_hash}")

    cond do
      provided_key_hash == masterkey_hash ->
        generate_api_key(conn, params, :masterkey)
      api_key_hash ->
        case ApiAuth.get_authenticated_api_key(api_key_hash) do
          {:ok, authenticated_key} -> generate_api_key(conn, params, {:api_key, authenticated_key})
          {:error, reason} ->
            conn
            |> put_status(:unauthorized)
            |> json_response(%{error: reason})
        end
      true ->
        conn
        |> put_status(:unauthorized)
        |> json_response(%{error: "Unauthorized"})
    end
  end

  defp generate_api_key(conn, params, auth_type) do
    with {:ok, key_type} <- validate_key_type(params["type"]),
         {:ok, _} <- authorize_key_generation(auth_type, key_type),
         {new_key, key_hash} <- ApiAuth.generate_api_key(),
         changeset <- ApiKey.changeset(%ApiKey{}, %{
            key_hash: key_hash,
            type: key_type,
            name: params["name"] || "Generated #{key_type}",
            description: params["description"] || "Generated with #{inspect(auth_type)}",
            created_by: case auth_type do
              :masterkey -> "masterkey"
              {:api_key, _} -> "api_key"
            end
         }),
         {:ok, api_key} <- Repo.insert(changeset) do
      Logger.info("API Key generated - Type: #{key_type}, Hash: #{api_key.key_hash}, Created By: #{api_key.created_by}")
      conn
      |> put_status(:created)
      |> json_response(%{
        key: new_key,
        key_id: key_hash,
        type: api_key.type,
        message: "API Key #{key_type} generated successfully",
      })
    else
      {:error, :invalid_key_type} ->
        Logger.warn("API Key generation failed - Invalid key type")
        conn
        |> put_status(:bad_request)
        |> json_response(%{error: "Invalid key type"})
      {:error, :unauthorized_key_generation} ->
        Logger.warn("API Key generation failed - Unauthorized to generate keys")
        conn
        |> put_status(:unauthorized)
        |> json_response(%{error: "Unauthorized to generate keys"})
      {:error, :unauthorized_operator_key_generation} ->
        Logger.warn("API Key generation failed - Unauthorized to generate operator keys")
        conn
        |> put_status(:unauthorized)
        |> json_response(%{error: "Unauthorized to generate operator keys"})
      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        Logger.warn("API Key generation failed - Validation errors: #{inspect(errors)}")
        conn
        |> put_status(:unprocessable_entity)
        |> json_response(%{errors: errors})
      {:error, reason} ->
        Logger.error("API Key generation failed - Unexpected error: #{inspect(reason)}")
        conn
        |> put_status(:internal_server_error)
        |> json_response(%{error: "An unexpected error occurred"})
    end
  end

  defp validate_key_type(type) when type in ["operator_key", "agent_key", "reader_key"],
    do: {:ok, type}
  defp validate_key_type(_), do: {:error, :invalid_key_type}

  defp authorize_key_generation(:masterkey, _), do: {:ok, :authorized}
  defp authorize_key_generation({:api_key, %ApiKey{type: "operator_key"}}, _), do: {:ok, :authorized}
  defp authorize_key_generation({:api_key, _}, "operator_key"), do: {:error, :unauthorized_operator_key_generation}
  defp authorize_key_generation({:api_key, _}, _), do: {:error, :unauthorized_key_generation}

  defp json_response(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(conn.status || 200, Jason.encode!(data))
  end
end
