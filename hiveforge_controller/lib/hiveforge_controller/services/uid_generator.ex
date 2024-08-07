defmodule HiveforgeController.Services.UIDGenerator do
  def generate do
    Uniq.UUID.uuid7()
  end
end
