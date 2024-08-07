defmodule HiveforgeController.Controllers.HashController do
  use Plug.Builder
  alias HiveforgeController.Services.HashProcessingService
  alias HiveforgeController.Storage.StorageService
  require Logger

  @max_payload_size 100 * 1024 * 1024  # 100 MB

  def init(opts), do: opts

  def call(conn, opts) do
    action = opts[:action] || :receive_hash
    apply(__MODULE__, action, [conn, opts])
  end

  def receive_hash(conn, _opts) do
    with {:ok, body} <- get_body(conn),
         {:ok, parsed_body} <- parse_json(body),
         :ok <- store_raw_json(parsed_body),
         {:ok, job_id} <- start_processing_job(parsed_body) do
      Logger.info("Successfully received and started processing hash result. Job ID: #{job_id}")
      send_json_response(conn, :accepted, %{job_id: job_id})
    else
      {:error, :payload_too_large} ->
        Logger.warn("Received payload too large")
        send_json_response(conn, :request_entity_too_large, %{error: "Payload too large"})
      {:error, :json_parse_error, reason} ->
        Logger.error("Failed to parse JSON: #{inspect(reason, pretty: true)}")
        send_json_response(conn, :bad_request, %{error: "Invalid JSON: #{inspect(reason)}"})
      {:error, :s3_storage_error, reason} ->
        Logger.error("Failed to store raw JSON in S3: #{inspect(reason)}")
        send_json_response(conn, :internal_server_error, %{error: "Failed to store raw JSON: #{inspect(reason)}"})
      {:error, reason} ->
        Logger.error("Error processing hash result: #{inspect(reason)}")
        send_json_response(conn, :internal_server_error, %{error: "An unexpected error occurred"})
    end
  end

  defp get_body(conn) do
    body = case conn.assigns[:raw_body] do
      nil ->
        Logger.debug("No raw_body in assigns, reading from conn")
        {:ok, body, _conn} = Plug.Conn.read_body(conn, length: @max_payload_size)
        body
      raw_body ->
        Logger.debug("Using raw_body from assigns, size: #{byte_size(raw_body)} bytes")
        raw_body
    end

    if byte_size(body) > @max_payload_size do
      Logger.warn("Payload size (#{byte_size(body)} bytes) exceeds maximum allowed size")
      {:error, :payload_too_large}
    else
      Logger.debug("Body size: #{byte_size(body)} bytes")
      {:ok, body}
    end
  end

  defp parse_json(body) do
    case Jason.decode(body) do
      {:ok, parsed} ->
        Logger.debug("Successfully parsed JSON body")
        {:ok, parsed}
      {:error, %Jason.DecodeError{} = reason} ->
        Logger.error("JSON parse error: #{inspect(reason, pretty: true)}")
        Logger.error("First 100 characters of body: #{String.slice(body, 0..99)}")
        {:error, :json_parse_error, reason}
    end
  end

  defp store_raw_json(parsed_body) do
    s3_key = StorageService.generate_s3_key("hash_result_#{:os.system_time(:millisecond)}.json")
    Logger.info("Storing raw JSON in S3 with key: #{s3_key}")
    case StorageService.upload_to_s3(s3_key, Jason.encode!(parsed_body)) do
      {:ok, _} ->
        Logger.info("Successfully stored raw JSON in S3")
        :ok
      {:error, reason} ->
        Logger.error("Failed to store raw JSON in S3: #{inspect(reason)}")
        {:error, :s3_storage_error, reason}
    end
  end

  defp start_processing_job(parsed_body) do
    Logger.info("Starting hash processing job")
    case HashProcessingService.process_hash_result(parsed_body) do
      {:ok, {:ok, %HiveforgeController.Schemas.HashResult{uid: hash_result_uid}}} ->
        # this is the low-effort path, shouldn't be double ok but it sometimes do
        Logger.info("Successfully started hash processing job. Hash Result UID: #{hash_result_uid}")
        {:ok, hash_result_uid}
      {:ok, %HiveforgeController.Schemas.HashResult{uid: hash_result_uid}} ->
        Logger.info("Successfully started hash processing job. Hash Result UID: #{hash_result_uid}")
        {:ok, hash_result_uid}
      {:error, reason} ->
        Logger.error("Failed to start hash processing job: #{inspect(reason)}")
        {:error, reason}
      unexpected ->
        Logger.error("Unexpected result from process_hash_result: #{inspect(unexpected)}")
        {:error, :unexpected_result}
    end
  end

  defp send_json_response(conn, status, body) do
    Logger.info("Sending JSON response with status: #{status}")
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
