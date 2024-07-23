defmodule HiveforgeController.HashController do
  import Plug.Conn
  require Logger
  alias HiveforgeController.{ApiKeyService, HashService}

  @max_log_length 200

  @spec init(any) :: any
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword) :: Plug.Conn.t()
  def call(conn, action: :receive_hash) do
    receive_hash(conn)
  end

  defp receive_hash(conn) do
    Logger.info("HashController: Receiving hash")
    claims = conn.assigns[:current_user]
    Logger.debug("HashController: Authorizing action :submit_hash_result for claims: #{truncate_inspect(claims)}")
    Logger.debug("HashController: conn.assigns: #{truncate_inspect(conn.assigns)}")

    case ApiKeyService.authorize_action(claims, :submit_hash_result) do
      :ok ->
        Logger.info("HashController: Action authorized")
        process_hash(conn)
      {:error, reason} ->
        Logger.error("HashController: Unauthorized action: #{inspect(reason)}")
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Jason.encode!(%{error: "Unauthorized", details: reason}))
        |> halt()
    end
  end

  defp process_hash(conn) do
    case parse_body(conn) do
      {:ok, hash_result} ->
        case HashService.process_hash_result(hash_result) do
          {:ok, processed_result} ->
            Logger.debug("Processed result: #{inspect(processed_result)}")
            response = %{
              message: "Hash received and processed successfully",
              result: %{
                id: processed_result.id,
                root_path: processed_result.root_path,
                total_files: processed_result.total_files,
                total_size: processed_result.total_size,
                hashing_time: processed_result.hashing_time,
                status: processed_result.status
              }
            }
            Logger.debug("Response: #{inspect(response)}")
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(response))

          {:error, reason} ->
            Logger.error("HashController: Failed to store hash result in database: #{inspect(reason)}")
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(500, Jason.encode!(%{error: "Failed to process hash result", details: inspect(reason)}))
        end

      {:error, reason} ->
        Logger.error("HashController: Failed to parse body: #{inspect(reason)}")
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid request body", details: inspect(reason)}))
    end
  end

  defp log_hash_result(hash_result) do
    Logger.info("HashController: Hash result keys: #{truncate_inspect(Map.keys(hash_result))}")
    Logger.debug("HashController: Hash result sample: #{truncate_inspect(hash_result)}")
  end

  defp truncate_inspect(data, max_length \\ @max_log_length) do
    inspected = inspect(data, limit: :infinity)
    if String.length(inspected) > max_length do
      "#{String.slice(inspected, 0, max_length)}..."
    else
      inspected
    end
  end

  defp parse_body(conn) do
    Logger.debug("HashController: Parsing body")
    case conn.assigns[:raw_body] do
      nil ->
        Logger.error("HashController: No raw body found in assigns")
        {:error, "No raw body found"}
      raw_body ->
        Logger.debug("HashController: Raw body found, size: #{byte_size(raw_body)} bytes")
        case Jason.decode(raw_body) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} ->
            Logger.error("HashController: JSON parsing error: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end
end
