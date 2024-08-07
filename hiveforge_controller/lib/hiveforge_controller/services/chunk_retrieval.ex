defmodule HiveforgeController.Services.ChunkRetrievalService do
  import Ecto.Query
  alias HiveforgeController.Repo
  alias HiveforgeController.Schemas.{FileResult, FileChunk, Chunk}

  @chunk_batch_size 1000

  def get_file_chunks(file_result_id) do
    query = from fc in FileChunk,
      join: c in Chunk, on: fc.chunk_id == c.id,
      where: fc.file_result_id == ^file_result_id,
      order_by: fc.sequence,
      select: %{sequence: fc.sequence, offset: fc.offset, hash: c.hash, size: c.size}

    Repo.stream(query)
    |> Stream.chunk_every(@chunk_batch_size)
    |> Stream.flat_map(& &1)
  end

  def get_file_info(file_name) do
    query = from fr in FileResult,
      where: fr.name == ^file_name,
      select: %{
        id: fr.id,
        name: fr.name,
        size: fr.size,
        hash: fr.hash,
        total_chunks: fr.total_chunks
      },
      limit: 1

    Repo.one(query)
  end
end
