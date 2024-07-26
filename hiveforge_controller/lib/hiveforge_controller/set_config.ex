defmodule HiveforgeController.SetConfig do
  @moduledoc """
  Module to handle configuration settings. Currently only S3 config,
  , but migrate other persistent_term settings here as well.
  """

  @persistent_keys [:s3_backend, :s3_access_key_id, :s3_secret_access_key, :s3_bucket_name, :s3_region, :s3_endpoint]

  @spec init() :: :ok
  def init do
    config = %{
      s3_backend: System.get_env("S3_BACKEND"),
      s3_access_key_id: System.get_env("S3_ACCESS_KEY_ID"),
      s3_secret_access_key: System.get_env("S3_SECRET_ACCESS_KEY"),
      s3_bucket_name: System.get_env("S3_BUCKET_NAME"),
      s3_region: System.get_env("S3_REGION") || "",
      s3_endpoint: System.get_env("S3_ENDPOINT") || ""
    }

    IO.inspect(config, label: "Config being set")

    Enum.each(@persistent_keys, fn key ->
      value = Map.get(config, key)
      :persistent_term.put(key, value)
      IO.puts("Setting #{key} to #{value}")
    end)

    :ok
  end

  @spec get(atom) :: any
  def get(key) do
    :persistent_term.get(key)
  end
end
