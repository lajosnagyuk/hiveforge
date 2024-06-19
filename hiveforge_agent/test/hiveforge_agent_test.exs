defmodule HiveforgeAgentTest do
  use ExUnit.Case
  doctest HiveforgeAgent

  test "greets the world" do
    assert HiveforgeAgent.hello() == :world
  end
end
