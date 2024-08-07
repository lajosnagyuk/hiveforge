defmodule HiveforgeController.Schemas.Type.SanitizedString do
  use Ecto.Type
  alias HiveforgeController.Services.RobustStringSanitizer

  def type, do: :string

  def cast(value) when is_binary(value) do
    {:ok, RobustStringSanitizer.sanitize(value)}
  end
  def cast(value) when is_nil(value), do: {:ok, nil}
  def cast(_), do: :error

  def load(value), do: {:ok, value}

  def dump(value) when is_binary(value) do
    {:ok, RobustStringSanitizer.sanitize(value)}
  end
  def dump(nil), do: {:ok, nil}
  def dump(_), do: :error
end
