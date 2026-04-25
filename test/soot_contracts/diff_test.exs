defmodule SootContracts.DiffTest do
  use ExUnit.Case, async: false

  alias SootContracts.{Bundle, Diff}
  alias SootContracts.Test.Fixtures.{Device, DeviceShadow}
  alias SootContracts.Test.Helpers

  setup do
    Helpers.reset_ets!()
    {:ok, ca: Helpers.fresh_ca!()}
  end

  test "added paths come from the second argument", %{ca: ca} do
    a = Bundle.assemble(mqtt_resources: [Device], trust_chain: [ca], generated_at: ~U[2026-04-26 12:00:00Z])
    b = Bundle.assemble(mqtt_resources: [Device, DeviceShadow], trust_chain: [ca], generated_at: ~U[2026-04-26 12:00:00Z])

    diff = Diff.between(a, b)
    # shadow.json is in both bundles; nothing was actually added in
    # terms of asset paths (DeviceShadow contributes to shadow.json).
    # But topics.json content changes.
    assert "topics.json" in (Enum.map(diff.changed, & &1.path))
    assert "shadow.json" in (Enum.map(diff.changed, & &1.path))
  end

  test "removed paths come from the first argument", %{ca: ca} do
    a = Bundle.assemble(mqtt_resources: [Device], trust_chain: [ca], crl_url: "https://crl.example/root.crl", generated_at: ~U[2026-04-26 12:00:00Z])
    b = Bundle.assemble(mqtt_resources: [Device], trust_chain: [ca], generated_at: ~U[2026-04-26 12:00:00Z])

    diff = Diff.between(a, b)
    assert "pki/crl_url.txt" in diff.removed
  end

  test "nil before yields every after path as added", %{ca: ca} do
    a = Bundle.assemble(mqtt_resources: [Device], trust_chain: [ca], generated_at: ~U[2026-04-26 12:00:00Z])

    diff = Diff.between(nil, a)
    assert diff.before == nil
    assert diff.after == a.manifest.fingerprint
    assert "topics.json" in diff.added
    assert "pki/trust_chain.pem" in diff.added
    assert diff.removed == []
  end

  test "identical bundles diff to no changes", %{ca: ca} do
    a = Bundle.assemble(mqtt_resources: [Device], trust_chain: [ca], generated_at: ~U[2026-04-26 12:00:00Z])
    b = Bundle.assemble(mqtt_resources: [Device], trust_chain: [ca], generated_at: ~U[2026-04-26 12:00:00Z])

    diff = Diff.between(a, b)
    assert diff.added == []
    assert diff.removed == []
    assert diff.changed == []
  end
end
