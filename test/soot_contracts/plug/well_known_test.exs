defmodule SootContracts.Plug.WellKnownTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias SootContracts.{Bundle, Plug.WellKnown, Publisher}
  alias SootContracts.Test.Fixtures.Device
  alias SootContracts.Test.Helpers

  setup do
    Helpers.reset_ets!()
    ca = Helpers.fresh_ca!()

    bundle =
      Bundle.assemble(
        mqtt_resources: [Device],
        trust_chain: [ca],
        generated_at: ~U[2026-04-26 12:00:00Z]
      )
      |> Bundle.sign(ca)

    row = Publisher.publish!(bundle, ca)
    {:ok, ca: ca, bundle: bundle, row: row}
  end

  defp run_get(path, headers \\ []) do
    conn(:get, path)
    |> apply_headers(headers)
    |> WellKnown.call(WellKnown.init([]))
  end

  defp apply_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {k, v}, c -> put_req_header(c, k, v) end)
  end

  describe "GET /.well-known/soot/contract" do
    test "200 returns the current manifest", ctx do
      conn = run_get("/.well-known/soot/contract")
      assert conn.status == 200
      decoded = Jason.decode!(conn.resp_body)
      assert decoded["fingerprint"] == ctx.bundle.manifest.fingerprint
      assert get_resp_header(conn, "etag") == [~s("#{ctx.bundle.manifest.fingerprint}")]
    end

    test "If-None-Match returns 304" do
      first = run_get("/.well-known/soot/contract")
      [etag] = get_resp_header(first, "etag")

      second = run_get("/.well-known/soot/contract", [{"if-none-match", etag}])
      assert second.status == 304
      assert second.resp_body == ""
    end

    test "404 when no current bundle exists" do
      Helpers.reset_ets!()
      conn = run_get("/.well-known/soot/contract")
      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "no_current_bundle"
    end
  end

  describe "GET /.well-known/soot/contract/:fingerprint" do
    test "200 with the manifest of that bundle", ctx do
      conn = run_get("/.well-known/soot/contract/#{ctx.bundle.manifest.fingerprint}")
      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["fingerprint"] == ctx.bundle.manifest.fingerprint
    end

    test "404 on unknown fingerprint" do
      conn = run_get("/.well-known/soot/contract/abc123")
      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "unknown_fingerprint"
    end
  end

  describe "GET /.well-known/soot/contract/:fingerprint/:asset" do
    test "200 with the asset bytes and the right content-type", ctx do
      fp = ctx.bundle.manifest.fingerprint

      conn = run_get("/.well-known/soot/contract/#{fp}/topics.json")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
      assert is_binary(conn.resp_body)
      assert byte_size(conn.resp_body) == ctx.bundle.manifest.assets["topics.json"].size
    end

    test "200 .pem with x-pem-file content-type", ctx do
      fp = ctx.bundle.manifest.fingerprint
      conn = run_get("/.well-known/soot/contract/#{fp}/pki/trust_chain.pem")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/x-pem-file; charset=utf-8"]
    end

    test "404 on unknown asset path", ctx do
      fp = ctx.bundle.manifest.fingerprint
      conn = run_get("/.well-known/soot/contract/#{fp}/no/such.json")
      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "unknown_asset"
    end

    test "ETag for asset is fingerprint:path; If-None-Match returns 304", ctx do
      fp = ctx.bundle.manifest.fingerprint
      first = run_get("/.well-known/soot/contract/#{fp}/topics.json")
      [etag] = get_resp_header(first, "etag")
      assert etag == ~s("#{fp}:topics.json")

      second = run_get("/.well-known/soot/contract/#{fp}/topics.json", [{"if-none-match", etag}])
      assert second.status == 304
    end
  end

  describe "non-GET" do
    test "405 method not allowed" do
      conn =
        conn(:post, "/.well-known/soot/contract")
        |> WellKnown.call(WellKnown.init([]))

      assert conn.status == 405
      assert Jason.decode!(conn.resp_body)["error"] == "method_not_allowed"
    end
  end

  describe "unrecognised paths" do
    test "404 with no_route" do
      conn = run_get("/something/else")
      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "no_route"
    end
  end
end
