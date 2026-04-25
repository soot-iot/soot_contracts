defmodule SootContracts.BundleTest do
  use ExUnit.Case, async: false

  alias SootContracts.Bundle
  alias SootContracts.Test.Fixtures.{Device, DeviceShadow, Vibration}
  alias SootContracts.Test.Helpers

  setup do
    Helpers.reset_ets!()
    {:ok, ca: Helpers.fresh_ca!()}
  end

  describe "assemble/1" do
    test "produces every expected asset path", %{ca: ca} do
      bundle = Bundle.assemble(
        mqtt_resources: [Device, DeviceShadow],
        telemetry_streams: [Vibration],
        trust_chain: [ca],
        crl_url: "https://crl.example/root.crl",
        generated_at: ~U[2026-04-26 12:00:00Z]
      )

      paths = bundle.assets |> Map.keys() |> Enum.sort()

      assert "topics.json" in paths
      assert "commands.json" in paths
      assert "shadow.json" in paths
      assert "streams/vibration.json" in paths
      assert "streams/vibration.arrow_schema" in paths
      assert "pki/trust_chain.pem" in paths
      assert "pki/fingerprints.json" in paths
      assert "pki/crl_url.txt" in paths
    end

    test "produces a stamped ISO datetime in the manifest", %{ca: ca} do
      bundle = Bundle.assemble(
        mqtt_resources: [Device],
        trust_chain: [ca],
        generated_at: ~U[2026-04-26 12:00:00Z]
      )

      assert bundle.manifest.generated_at == ~U[2026-04-26 12:00:00Z]
    end

    test "is deterministic across runs (same inputs → same fingerprint)", %{ca: ca} do
      a =
        Bundle.assemble(
          mqtt_resources: [Device, DeviceShadow],
          telemetry_streams: [Vibration],
          trust_chain: [ca],
          generated_at: ~U[2026-04-26 12:00:00Z]
        )

      b =
        Bundle.assemble(
          mqtt_resources: [Device, DeviceShadow],
          telemetry_streams: [Vibration],
          trust_chain: [ca],
          generated_at: ~U[2026-04-26 12:00:00Z]
        )

      assert a.manifest.fingerprint == b.manifest.fingerprint
    end

    test "fingerprint changes when any input changes", %{ca: ca} do
      a =
        Bundle.assemble(
          mqtt_resources: [Device, DeviceShadow],
          telemetry_streams: [Vibration],
          trust_chain: [ca],
          generated_at: ~U[2026-04-26 12:00:00Z]
        )

      b =
        Bundle.assemble(
          mqtt_resources: [Device],
          telemetry_streams: [Vibration],
          trust_chain: [ca],
          generated_at: ~U[2026-04-26 12:00:00Z]
        )

      refute a.manifest.fingerprint == b.manifest.fingerprint
    end

    test "manifest assets index lists each path with sha256 + size", %{ca: ca} do
      bundle = Bundle.assemble(
        mqtt_resources: [Device],
        trust_chain: [ca],
        generated_at: ~U[2026-04-26 12:00:00Z]
      )

      Enum.each(bundle.manifest.assets, fn {_path, meta} ->
        assert meta.sha256 =~ ~r/^[0-9a-f]{64}$/
        assert is_integer(meta.size) and meta.size > 0
      end)
    end

    test "crl_url is omitted when not provided", %{ca: ca} do
      bundle = Bundle.assemble(
        mqtt_resources: [Device],
        trust_chain: [ca],
        generated_at: ~U[2026-04-26 12:00:00Z]
      )

      refute Map.has_key?(bundle.assets, "pki/crl_url.txt")
    end
  end

  describe "sign/2 + verify/2" do
    test "signed bundles verify against the same CA", %{ca: ca} do
      signed =
        Bundle.assemble(
          mqtt_resources: [Device],
          trust_chain: [ca],
          generated_at: ~U[2026-04-26 12:00:00Z]
        )
        |> Bundle.sign(ca)

      assert {:ok, ^signed} = Bundle.verify(signed, ca)
      assert signed.manifest.signed_by == ca.fingerprint
      assert signed.manifest.signature
    end

    test "tampering an asset's bytes (without updating the manifest) fails verify", %{ca: ca} do
      signed =
        Bundle.assemble(
          mqtt_resources: [Device],
          trust_chain: [ca],
          generated_at: ~U[2026-04-26 12:00:00Z]
        )
        |> Bundle.sign(ca)

      tampered = put_in(signed.assets["topics.json"], "tampered")
      assert {:error, {:asset_mismatch, "topics.json"}} = Bundle.verify(tampered, ca)
    end

    test "tampering the manifest also fails verify", %{ca: ca} do
      signed =
        Bundle.assemble(
          mqtt_resources: [Device],
          trust_chain: [ca],
          generated_at: ~U[2026-04-26 12:00:00Z]
        )
        |> Bundle.sign(ca)

      tampered = put_in(signed.manifest.assets["topics.json"][:size], 99_999)
      assert {:error, _} = Bundle.verify(tampered, ca)
    end

    test "verify against a different CA fails", %{ca: ca} do
      other_ca = Helpers.fresh_ca!("other")

      signed =
        Bundle.assemble(
          mqtt_resources: [Device],
          trust_chain: [ca],
          generated_at: ~U[2026-04-26 12:00:00Z]
        )
        |> Bundle.sign(ca)

      assert {:error, :invalid_signature} = Bundle.verify(signed, other_ca)
    end

    test "verify on an unsigned bundle errors", %{ca: ca} do
      bundle =
        Bundle.assemble(
          mqtt_resources: [Device],
          trust_chain: [ca],
          generated_at: ~U[2026-04-26 12:00:00Z]
        )

      assert {:error, :unsigned_bundle} = Bundle.verify(bundle, ca)
    end
  end
end
