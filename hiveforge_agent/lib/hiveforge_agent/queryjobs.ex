defmodule HiveforgeAgent.Queryjobs do
  require Logger

  def queryActiveJobs do
    Logger.info("Performing scheduled job...")

    api_endpoint =
      Application.get_env(
        :hiveforge_agent,
        HiveforgeAgent.Queryjobs,
        :hiveforge_controller_api_endpoint
      )

    ca_cert_path = Application.get_env(:hiveforge_agent, HiveforgeAgent.Queryjobs, :ca_cert_path)

    Logger.debug("API Endpoint: #{inspect(api_endpoint)}")
    Logger.debug("CA Cert Path: #{inspect(ca_cert_path)}")

    if api_endpoint do
      if ca_cert_path && File.exists?(ca_cert_path) do
        Logger.debug("CA Cert file exists at: #{inspect(ca_cert_path)}")
      else
        Logger.error("CA Cert file does not exist at: #{inspect(ca_cert_path)}")
      end

      # Function to construct the URL
      url =
        if String.ends_with?(api_endpoint, "/") do
          "#{api_endpoint}api/v1/activejobs"
        else
          "#{api_endpoint}/api/v1/activejobs"
        end

      Logger.debug("Constructed URL: #{url}")

      options =
        if ca_cert_path && File.exists?(ca_cert_path) do
          [
            ssl: [
              cacertfile: ca_cert_path
            ]
          ]
        else
          []
        end

      Logger.info("Making HTTP request to: #{url}")

      case HTTPoison.get(url, [], options) do
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
