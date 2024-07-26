defmodule HiveforgeController.Controllers.HashController do
  use Plug.Builder
  alias HiveforgeController.Services.HashProcessingService
  alias HiveforgeController.Storage.StorageService
  require Logger

  def init(opts), do: opts

  def call(conn, opts) do
    action = opts[:action] || :receive_hash
    apply(__MODULE__, action, [conn, opts])
  end

  def receive_hash(conn, _opts) do
    with {:ok, raw_body} <- get_raw_body(conn),
         {:ok, parsed_body} <- parse_json(raw_body),
         :ok <- store_raw_json(parsed_body),
         {:ok, %HiveforgeController.Schemas.HashResult{id: hash_result_id} = hash_result} <- HashProcessingService.process_hash_result(parsed_body) do

      Logger.info("Successfully processed hash result: #{hash_result_id}")
      send_json_response(conn, :created, %{hash_result_id: hash_result_id})
    else
      {:error, :no_raw_body} ->
        send_json_response(conn, :bad_request, %{error: "No raw body provided"})
      {:error, :json_parse_error, reason} ->
        send_json_response(conn, :bad_request, %{error: "Invalid JSON: #{reason}"})
      {:error, :s3_storage_error, reason} ->
        send_json_response(conn, :internal_server_error, %{error: "Failed to store raw JSON: #{reason}"})
      {:error, {:validation_error, changeset}} ->
        errors = Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
        send_json_response(conn, :unprocessable_entity, %{errors: errors})
      {:error, reason} ->
        Logger.error("Error processing hash result: #{inspect(reason)}")
        send_json_response(conn, :internal_server_error, %{error: "An unexpected error occurred"})
    end
  end


  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp get_raw_body(conn) do
    case Map.get(conn.assigns, :raw_body) do
      nil -> {:error, :no_raw_body}
      raw_body -> {:ok, raw_body}
    end
  end

  defp parse_json(raw_body) do
    case Jason.decode(raw_body) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, :json_parse_error, reason}
    end
  end

  defp store_raw_json(parsed_body) do
    s3_key = StorageService.generate_s3_key("hash_result_#{:os.system_time(:millisecond)}.json")
    case StorageService.upload_to_s3(s3_key, Jason.encode!(parsed_body)) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, :s3_storage_error, reason}
    end
  end

  defp send_json_response(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp changeset_error_to_map(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
