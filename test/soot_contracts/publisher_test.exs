defmodule SootContracts.PublisherTest do
  use ExUnit.Case, async: false

  alias SootContracts.{Bundle, BundleRow, Publisher}
  alias SootContracts.Test.Fixtures.Device
  alias SootContracts.Test.Helpers

  setup do
    Helpers.reset_ets!()
    {:ok, ca: Helpers.fresh_ca!()}
  end

  test "publish! persists a row and marks it current", %{ca: ca} do
    bundle =
      Bundle.assemble(
        mqtt_resources: [Device],
        trust_chain: [ca],
        generated_at: ~U[2026-04-26 12:00:00Z]
      )
      |> Bundle.sign(ca)

    row = Publisher.publish!(bundle, ca)

    assert row.fingerprint == bundle.manifest.fingerprint
    assert row.version == 1
    assert row.status == :current
    assert row.signed_by_ca_id == ca.id
  end

  test "publish! is idempotent on fingerprint", %{ca: ca} do
    bundle =
      Bundle.assemble(
        mqtt_resources: [Device],
        trust_chain: [ca],
        generated_at: ~U[2026-04-26 12:00:00Z]
      )
      |> Bundle.sign(ca)

    a = Publisher.publish!(bundle, ca)
    b = Publisher.publish!(bundle, ca)

    assert a.id == b.id
  end

  test "a new fingerprint supersedes the previous current", %{ca: ca} do
    first =
      Bundle.assemble(
        mqtt_resources: [Device],
        trust_chain: [ca],
        generated_at: ~U[2026-04-26 12:00:00Z]
      )
      |> Bundle.sign(ca)
      |> Publisher.publish!(ca)

    second =
      Bundle.assemble(
        mqtt_resources: [Device],
        trust_chain: [ca],
        crl_url: "https://crl.example.com/root.crl",
        generated_at: ~U[2026-04-26 13:00:00Z]
      )
      |> Bundle.sign(ca)
      |> Publisher.publish!(ca)

    assert second.version == 2

    {:ok, refreshed_first} = Ash.get(BundleRow, first.id, authorize?: false)
    assert refreshed_first.status == :superseded

    assert Publisher.current().id == second.id
  end

  test "current/0 returns nil before any publish" do
    assert Publisher.current() == nil
  end
end
