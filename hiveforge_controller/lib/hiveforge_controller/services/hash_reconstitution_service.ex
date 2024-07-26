defmodule HiveforgeController.Services.HashReconstitutionService do
  alias HiveforgeController.Repo
  alias HiveforgeController.Schemas.{HashResult, FileEntry, FileChunk}
  alias HiveforgeController.Storage.StorageService
  require Logger
  alias HiveforgeController.SetConfig
  import Ecto.Query

  def reconstitute_hash_result(hash_result_id) do
    with {:ok, hash_result} <- get_hash_result(hash_result_id),
         {:ok, file_entries} <- get_file_entries(hash_result_id),
         {:ok, reconstituted_result} <- build_result_structure(hash_result, file_entries) do
      {:ok, reconstituted_result}
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

  defp get_file_entries(hash_result_id) do
    query = from fe in FileEntry,
      where: fe.hash_result_id == ^hash_result_id,
      preload: [file_chunks: [chunk: []]]

    case Repo.all(query) do
      [] -> {:error, :no_files_found}
      file_entries -> {:ok, file_entries}
    end
  end

  defp build_result_structure(hash_result, file_entries) do
    directory_structure = build_directory_structure(file_entries)

    result = %{
      root: hash_result.root_path,
      dir: directory_structure,
      size: hash_result.total_size,
      files: hash_result.total_files,
      time: hash_result.hashing_time
    }

    {:ok, result}
  end

  defp build_directory_structure(file_entries) do
    file_entries
    |> Enum.map(&file_entry_to_map/1)
    |> build_tree()
  end

  defp file_entry_to_map(file_entry) do
    chunks = file_entry.file_chunks
    |> Enum.sort_by(& &1.sequence)
    |> Enum.map(& &1.chunk.hash)

    %{
      name: file_entry.file_name,
      path: file_entry.path,
      type: "file",
      size: file_entry.size,
      hashes: %{
        name: file_entry.file_name,
        chunkSize: file_entry.chunk_size,
        chunkCount: file_entry.chunk_count,
        hashes: chunks,
        size: file_entry.size
      }
    }
  end

  defp build_tree(file_maps) do
    file_maps
    |> Enum.reduce(%{}, fn file, acc ->
      path_parts = String.split(file.path, "/")
      put_in(acc, Enum.map(path_parts, &Access.key(&1, %{})), file)
    end)
    |> flatten_tree()
  end

  defp flatten_tree(tree) do
    tree
    |> Enum.map(fn {name, content} ->
      cond do
        content[:type] == "file" -> content
        true ->
          %{
            name: name,
            type: "directory",
            children: flatten_tree(content)
          }
      end
    end)
    |> Enum.sort_by(& &1.name)
  end
end
