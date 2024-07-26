defmodule HiveforgeController.Storage.StorageService do
  alias HiveforgeController.SetConfig
  require Logger

  @max_concurrency 10

  def store_chunks(chunks, s3_backend) do
    Logger.info("Storing #{length(chunks)} chunks")

    chunks
    |> Task.async_stream(
      fn chunk ->
        s3_key = generate_chunk_s3_key(chunk.hash)
        case upload_to_s3(s3_key, chunk.content) do
          {:ok, _} -> {:ok, %{hash: chunk.hash, s3_key: s3_key, s3_backend: s3_backend}}
          {:error, reason} -> {:error, chunk.hash, reason}
        end
      end,
      max_concurrency: @max_concurrency,
      timeout: 60_000
    )
    |> Enum.reduce({[], []}, fn
      {:ok, {:ok, result}}, {successes, failures} ->
        {[result | successes], failures}
      {:ok, {:error, hash, reason}}, {successes, failures} ->
        {successes, [{hash, reason} | failures]}
      {:exit, reason}, {successes, failures} ->
        Logger.error("Task failed: #{inspect(reason)}")
        {successes, failures}
    end)
    |> case do
      {successes, []} -> {:ok, successes}
      {_, failures} -> {:error, failures}
    end
  end

  def store_file(content, metadata, s3_backend) do
    s3_key = generate_s3_key(metadata.file_name)
    Logger.info("Storing file: #{s3_key}")

    if byte_size(content) == 0 do
      Logger.info("Empty file detected, skipping S3 upload for: #{s3_key}")
      {:ok, %{s3_key: s3_key, s3_backend: s3_backend}}
    else
      Task.async(fn ->
        upload_to_s3(s3_key, content)
      end)
      |> Task.await(30_000)
      |> case do
        {:ok, _} -> {:ok, %{s3_key: s3_key, s3_backend: s3_backend}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def generate_s3_key(file_name) do
    unique_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    "files/#{unique_id}/#{file_name}"
  end

  def generate_chunk_s3_key(chunk_hash) do
    <<dir1::binary-size(4), dir2::binary-size(4), _rest::binary>> = chunk_hash
    "chunks/#{dir1}/#{dir2}/#{chunk_hash}"
  end

  def upload_to_s3(s3_key, content) do
    Logger.debug("Uploading to S3: #{s3_key}")
    config = get_s3_config()
    bucket = SetConfig.get(:s3_bucket_name)

    ExAws.S3.put_object(bucket, s3_key, content)
    |> ExAws.request(config)
    |> case do
      {:ok, %{status_code: 200}} ->
        Logger.info("Successfully uploaded to S3: #{s3_key}")
        {:ok, s3_key}
      {:error, reason} ->
        Logger.error("Failed to upload to S3: #{s3_key}. Reason: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_s3_config do
    %{
      access_key_id: SetConfig.get(:s3_access_key_id),
      secret_access_key: SetConfig.get(:s3_secret_access_key),
      region: SetConfig.get(:s3_region),
      host: URI.parse(SetConfig.get(:s3_endpoint) || "").host,
      port: URI.parse(SetConfig.get(:s3_endpoint) || "").port,
      scheme: URI.parse(SetConfig.get(:s3_endpoint) || "").scheme || "http"
    }
  end
end
