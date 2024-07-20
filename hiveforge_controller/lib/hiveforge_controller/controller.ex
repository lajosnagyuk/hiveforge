defmodule HiveforgeController.Controller do
  defmacro __using__(_opts) do
    quote do
      import Plug.Conn
      import HiveforgeController.Controller

      def send_json(conn, status, data) do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(status, Jason.encode!(data))
      end
    end
  end
end
