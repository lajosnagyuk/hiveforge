defmodule HiveforgeFrontendTest do
  use ExUnit.Case
  doctest HiveforgeFrontend

  test "greets the world" do
    assert HiveforgeFrontend.hello() == :world
  end
end
