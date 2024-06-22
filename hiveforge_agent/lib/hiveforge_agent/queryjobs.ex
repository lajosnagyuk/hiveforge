defmodule HiveforgeAgent.Queryjobs do
  require Logger

  def queryActiveJobs do
    Logger.info("Performing scheduled job...")

    api_endpoint = System.get_env("HIVEFORGE_CONTROLLER_API_ENDPOINT")
    ca_cert_path = System.get_env("HIVEFORGE_CA_CERT_PATH")

    Logger.debug("API Endpoint: #{inspect(api_endpoint)}")
    Logger.debug("CA Cert Path: #{inspect(ca_cert_path)}")

    case File.open(ca_cert_path) do
      {:ok, file} ->
        Logger.debug("CA Cert used: #{inspect(file)}")
        File.close(file)

      {:error, reason} ->
        Logger.error("Failed to open CA Cert file: #{inspect(reason)}")
    end

    case File.read(ca_cert_path) do
      {:ok, content} ->
        IO.puts(content)

      {:error, reason} ->
        IO.puts("Failed to read file: #{reason}")
    end

    if api_endpoint do
      if ca_cert_path && File.exists?(ca_cert_path) do
        Logger.debug("CA Cert file exists at: #{inspect(ca_cert_path)}")
      else
        Logger.error("CA Cert file does not exist at: #{inspect(ca_cert_path)}")
      end

      url =
        if String.ends_with?(api_endpoint, "/") do
          "#{api_endpoint}api/v1/activejobs"
        else
          "#{api_endpoint}/api/v1/activejobs"
        end

      Logger.info("Making HTTP request to: #{url}")

      opts = [
        ssl_override: [
          cacertfile: ca_cert_path,
          verify: :verify_peer,
          depth: 3,
          secure_renegotiate: true,
          reuse_sessions: true,
          verify_fun: {&:ssl_verify_hostname.verify_fun/3, []}
        ]
      ]

      case HTTPoison.get(url, [], opts) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          Logger.info("Success: #{body}")

        {:ok, %HTTPoison.Response{status_code: status_code}} ->
          Logger.error("Request failed with status code: #{status_code}")

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("Request error: #{inspect(reason)}")
      end
    else
      Logger.error("HIVEFORGE_CONTROLLER_API_ENDPOINT is not set")
    end
  end
end
