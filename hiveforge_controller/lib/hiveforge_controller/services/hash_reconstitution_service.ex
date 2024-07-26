defmodule HiveforgeController.Services.HashReconstitutionService do
  alias HiveforgeController.Repo
  alias HiveforgeController.Schemas.{HashResult, DirectoryEntry, FileResult, Chunk, FileChunk}
  alias HiveforgeController.Storage.StorageService
  require Logger
  import Ecto.Query

  def reconstitute_hash_result(hash_result_id) do
    with {:ok, hash_result} <- get_hash_result(hash_result_id),
         {:ok, directory_structure} <- get_directory_structure(hash_result_id) do
      {:ok, build_result_structure(hash_result, directory_structure)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_hash_result(id) do
    case Repo.get(HashResult, id) do
      nil -> {:error, :not_found}
      hash_result -> {:ok, hash_result}
    end
  end

  defp get_directory_structure(hash_result_id) do
    query = from de in DirectoryEntry,
      where: de.hash_result_id == ^hash_result_id,
      preload: [file_result: [file_chunks: [chunk: []]]]

    case Repo.all(query) do
      [] -> {:error, :no_directory_structure_found}
      entries -> {:ok, build_tree(entries)}
    end
  end

  defp build_tree(entries) do
    entries
    |> Enum.group_by(& &1.parent_id)
    |> build_tree_recursive(nil)
    |> List.first()
  end

  defp build_tree_recursive(grouped_entries, parent_id) do
    grouped_entries
    |> Map.get(parent_id, [])
    |> Enum.map(fn entry ->
      children = build_tree_recursive(grouped_entries, entry.id)
      entry_to_map(entry, children)
    end)
  end

  defp entry_to_map(%DirectoryEntry{type: "file"} = entry, _children) do
    %{
      name: entry.name,
      type: "file",
      size: entry.size,
      file_result: file_result_to_map(entry.file_result)
    }
  end

  defp entry_to_map(%DirectoryEntry{type: "directory"} = entry, children) do
    %{
      name: entry.name,
      type: "directory",
      size: entry.size,
      children: children
    }
  end

  defp file_result_to_map(nil), do: nil
  defp file_result_to_map(file_result) do
    %{
      file_info: %{
        name: file_result.name,
        size: file_result.size,
        hash: file_result.hash
      },
      chunking_info: %{
        algorithm: file_result.algorithm,
        average_chunk_size: file_result.average_chunk_size,
        min_chunk_size: file_result.min_chunk_size,
        max_chunk_size: file_result.max_chunk_size,
        total_chunks: file_result.total_chunks
      },
      chunks: file_result.file_chunks
               |> Enum.sort_by(& &1.sequence)
               |> Enum.map(&chunk_to_map/1)
              }
  end

  defp chunk_to_map(file_chunk) do
    %{
      hash: file_chunk.chunk.hash,
      size: file_chunk.chunk.size,
      offset: file_chunk.offset
    }
  end

  defp build_result_structure(hash_result, directory_structure) do
    %{
      root: hash_result.root_path,
      dir: directory_structure,
      size: hash_result.total_size,
      files: hash_result.total_files,
      time: hash_result.hashing_time
    }
  end
end
