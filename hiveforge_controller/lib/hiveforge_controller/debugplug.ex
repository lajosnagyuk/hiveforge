defmodule HiveforgeController.DebugPlug do
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    Logger.info("DebugPlug: Request reached pre-GzipDecompressor stage")
    Logger.info("DebugPlug: Content-Encoding: #{inspect(Plug.Conn.get_req_header(conn, "content-encoding"))}")
    Logger.info("DebugPlug: Content-Type: #{inspect(Plug.Conn.get_req_header(conn, "content-type"))}")
    conn
  end
end
