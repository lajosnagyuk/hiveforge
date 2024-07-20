defmodule HiveforgeController.GzipDecompressor do
  require Logger
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "content-encoding") do
      ["gzip"] -> decompress_body(conn)
      _ -> conn
    end
  end

  defp decompress_body(conn) do
    {:ok, body, conn} = read_body(conn)
    Logger.info("GzipDecompressor: Read body, size: #{byte_size(body)} bytes")

    case :zlib.gunzip(body) do
      decompressed when is_binary(decompressed) ->
        Logger.info("GzipDecompressor: Successfully decompressed. New size: #{byte_size(decompressed)} bytes")
        conn = conn
          |> put_req_header("content-length", Integer.to_string(byte_size(decompressed)))
          |> delete_req_header("content-encoding")
          |> assign(:raw_body, decompressed)
        Logger.info("GzipDecompressor: Assigned raw_body, size: #{byte_size(conn.assigns[:raw_body])} bytes")
        conn
      {:error, reason} ->
        Logger.error("GzipDecompressor: Failed to decompress: #{inspect(reason)}")
        conn
    end
  rescue
    e ->
      Logger.error("GzipDecompressor: Error during decompression: #{inspect(e)}")
      conn
  end
end
