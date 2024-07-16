defmodule HiveforgeController.SessionStore do
  use GenServer

  @table_name :hiveforge_session

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    :ets.new(@table_name, [:set, :public, :named_table])
    {:ok, nil}
  end

  def table_name, do: @table_name
end
