defmodule HiveforgeController.ApiKeyController do
  use Plug.Builder
  alias HiveforgeController.{ApiAuth, ApiKey, Repo}
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)
    apply(__MODULE__, action, [conn, conn.params])
  end

  def generate_key(conn, params) do
    master_key = Application.get_env(:hiveforge_controller, :master_key)
    provided_key = get_req_header(conn, "x-master-key") |> List.first()

    if provided_key == master_key do
      generate_initial_operator_key(conn, params)
    else
      generate_key_with_api_key(conn, params)
    end
  end

  defp generate_initial_operator_key(conn, params) do
    new_key = ApiAuth.generate_api_key("operator_key")

    changeset =
      ApiKey.changeset(%ApiKey{}, %{
        key: new_key,
        type: "operator_key",
        name: params["name"] || "Initial Operator Key",
        description: params["description"] || "First operator key generated with master key",
        created_by: "master_key"
      })

    case Repo.insert(changeset) do
      {:ok, api_key} ->
        conn
        |> put_status(:created)
        |> json_response(%{
          key: api_key.key,
          message: "Initial operator key generated successfully"
        })

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json_response(%{errors: errors})
    end
  end

  defp validate_key_type(type) when type in ["operator_key", "agent_key", "reader_key"],
    do: {:ok, type}

  defp validate_key_type(_), do: {:error, "Invalid key type"}

  defp authorize_key_generation(%ApiKey{type: "operator_key"}, _), do: {:ok, :authorized}

  defp authorize_key_generation(_, "operator_key"),
    do: {:error, "Unauthorized to generate Operator keys"}

  defp authorize_key_generation(_, _), do: {:error, "Unauthorized to generate keys"}

  defp json_response(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(conn.status || 200, Jason.encode!(data))
  end
end
