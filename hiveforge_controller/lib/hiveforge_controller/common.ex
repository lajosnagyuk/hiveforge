defmodule HiveforgeController.Common do

  def hash_key(nil), do: "nil"
  def hash_key(key) do
    :crypto.hash(:sha256, key)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 8)  # Take first 8 characters of the hash
  end
end
