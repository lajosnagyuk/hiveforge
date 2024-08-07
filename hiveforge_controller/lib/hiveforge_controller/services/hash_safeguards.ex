defmodule HiveforgeController.Services.HashProcessingSafeguards do
  @max_depth 100
  @max_name_length 255

  def validate_directory_structure(dir_entry, current_depth \\ 0) do
    cond do
      current_depth > @max_depth ->
        {:error, "Maximum directory depth exceeded"}
      String.length(dir_entry["name"]) > @max_name_length ->
        {:error, "File or directory name too long: #{dir_entry["name"]}"}
      dir_entry["type"] == "file" && dir_entry["size"] == 0 ->
        {:ok, "Empty file detected: #{dir_entry["name"]}"}
      dir_entry["type"] == "directory" && (!dir_entry["children"] || Enum.empty?(dir_entry["children"])) ->
        {:ok, "Empty directory detected: #{dir_entry["name"]}"}
      dir_entry["type"] == "symlink" ->
        {:error, "Symbolic links are not supported: #{dir_entry["name"]}"}
      dir_entry["type"] not in ["file", "directory"] ->
        {:error, "Unsupported file type: #{dir_entry["type"]} for #{dir_entry["name"]}"}
      true ->
        if dir_entry["type"] == "directory" do
          Enum.reduce_while(dir_entry["children"], {:ok, nil}, fn child, acc ->
            case validate_directory_structure(child, current_depth + 1) do
              {:ok, _} -> {:cont, acc}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)
        else
          {:ok, nil}
        end
    end
  end
end
