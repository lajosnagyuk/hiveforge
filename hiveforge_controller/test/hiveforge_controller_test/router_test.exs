defmodule HiveforgeControllerTest.RouterTest do
  use ExUnit.Case, async: true

  use Plug.Test

  @opts HiveforgeController.Router.init([])

  test "return ok" do
    build_conn = conn(:get, "/")
    conn = HiveforgeController.Router.call(build_conn, @opts)

    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == "OK"
  end

  test "readiness ok" do
    build_conn = conn(:get, "/api/v1/readiness")
    conn = HiveforgeController.Router.call(build_conn, @opts)

    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == "OK"
  end

  test "health ok" do
    build_conn = conn(:get, "/api/v1/health")
    conn = HiveforgeController.Router.call(build_conn, @opts)

    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == "OK"
  end

  test "return 404" do
    build_conn = conn(:get, "/slabadaba")
    conn = HiveforgeController.Router.call(build_conn, @opts)

    assert conn.state == :sent
    assert conn.status == 404
    assert conn.resp_body == "Mit ni?"
  end

  test "active jobs 200" do
    build_conn = conn(:get, "/api/v1/activejobs")
    conn = HiveforgeController.Router.call(build_conn, @opts)

    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == "OK"
  end
end
