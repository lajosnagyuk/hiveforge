defmodule HiveforgeAgent.Queryjobs do
  require Logger

  def queryActiveJobs do
    Logger.info("Performing scheduled job...")

    case System.get_env("HIVEFORGE_CONTROLLER_API_ENDPOINT") do
      nil ->
        Logger.error("HIVEFORGE_CONTROLLER_API_ENDPOINT is not set")

      api_endpoint ->
        ca_cert_path = System.get_env("HIVEFORGE_CA_CERT_PATH", "")

        Logger.debug("API Endpoint: #{inspect(api_endpoint)}")
        Logger.debug("CA Cert Path: #{inspect(ca_cert_path)}")

        ca_cert_opts = get_ca_cert_opts(ca_cert_path)
        url = build_url(api_endpoint)

        Logger.info("Making HTTP request to: #{url}")

        make_http_request(url, ca_cert_opts)
    end
  end

  defp get_ca_cert_opts(""), do: []

  defp get_ca_cert_opts(ca_cert_path) do
    if File.exists?(ca_cert_path) do
      Logger.debug("CA Cert file exists at: #{inspect(ca_cert_path)}")

      [
        ssl: [
          cacertfile: ca_cert_path,
          verify: :verify_peer,
          depth: 3,
          secure_renegotiate: true,
          reuse_sessions: true,
          verify_fun: {&:ssl_verify_hostname.verify_fun/3, []}
        ]
      ]
    else
      Logger.error("CA Cert file does not exist at: #{inspect(ca_cert_path)}")
      []
    end
  end

  defp build_url(api_endpoint) do
    if String.ends_with?(api_endpoint, "/") do
      "#{api_endpoint}api/v1/activejobs"
    else
      "#{api_endpoint}/api/v1/activejobs"
    end
  end

  defp make_http_request(url, opts) do
    case HTTPoison.get(url, [], opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Logger.info("Success: #{body}")

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.error("Request failed with status code: #{status_code}")

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Request error: #{inspect(reason)}")
    end
  end
end
