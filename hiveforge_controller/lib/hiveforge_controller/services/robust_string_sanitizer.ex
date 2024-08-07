defmodule HiveforgeController.Services.RobustStringSanitizer do
  require Logger

  def sanitize(string) when is_binary(string) do
    case :unicode.characters_to_binary(string, :utf8, :utf8) do
      sanitized_string when is_binary(sanitized_string) ->
        sanitized_string
        |> String.replace(~r/[^\x20-\x7E\p{L}\p{N}\p{P}\p{Z}]/u, fn invalid_char ->
          Logger.warning("Sanitizing invalid character: #{inspect(invalid_char, base: :hex)}")
          "_"
        end)

      {:error, good_part, _} ->
        Logger.error("Invalid UTF-8 sequence found: #{inspect(string, base: :hex)}")
        String.replace(good_part, ~r/[^\x20-\x7E\p{L}\p{N}\p{P}\p{Z}]/u, "_")
    end
  end

  def sanitize(other) do
    Logger.warning("Non-binary value passed to sanitize: #{inspect(other)}")
    to_string(other)
  end
end
