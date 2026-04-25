defmodule SootContracts.SourcesTest do
  use ExUnit.Case, async: false

  alias SootContracts.Sources
  alias SootContracts.Test.Fixtures.{Device, DeviceShadow, Vibration}
  alias SootContracts.Test.Helpers

  setup do
    Helpers.reset_ets!()
    {:ok, ca: Helpers.fresh_ca!()}
  end

  describe "topics/1" do
    test "keys topics by inspected resource module name" do
      topics = Sources.topics([Device])

      assert Map.keys(topics) == [inspect(Device)]
    end

    test "renders each topic descriptor with the public fields" do
      [topic | _] = Sources.topics([Device])[inspect(Device)]

      assert is_binary(topic.pattern)
      assert topic.direction in [:inbound, :outbound]
      assert Map.has_key?(topic, :qos)
      assert Map.has_key?(topic, :payload_format)
    end

    test "empty input returns empty map" do
      assert Sources.topics([]) == %{}
    end
  end

  describe "commands/1" do
    test "only resources that declare actions appear" do
      commands = Sources.commands([Device, DeviceShadow])

      assert Map.has_key?(commands, inspect(Device))
      refute Map.has_key?(commands, inspect(DeviceShadow))
    end

    test "renders each action descriptor with the public fields" do
      [action | _] = Sources.commands([Device])[inspect(Device)]

      assert action.name == :reboot
      assert is_binary(action.topic)
    end
  end

  describe "shadows/1" do
    test "only resources using the Shadow extension appear" do
      shadows = Sources.shadows([Device, DeviceShadow])

      assert Map.has_key?(shadows, inspect(DeviceShadow))
      refute Map.has_key?(shadows, inspect(Device))
    end

    test "renders desired/reported attributes from the DSL" do
      shadow = Sources.shadows([DeviceShadow])[inspect(DeviceShadow)]

      assert :led in shadow.desired_attributes
      assert :uptime_s in shadow.reported_attributes
    end
  end

  describe "streams/1" do
    test "keys descriptors by stringified stream name" do
      streams = Sources.streams([Vibration])

      assert Map.has_key?(streams, "vibration")
    end

    test "carries fingerprint, schema, and ingest endpoint" do
      desc = Sources.streams([Vibration])["vibration"]

      assert desc.tenant_scope == :per_tenant
      assert desc.ingest_endpoint == "/ingest/vibration"
      assert desc.sequence_field == :sequence
      assert is_binary(desc.schema_fingerprint)
      assert is_map(desc.schema)
    end
  end

  describe "trust_chain/2" do
    test "joins PEMs and lists fingerprints", %{ca: ca} do
      result = Sources.trust_chain([ca])

      assert result.trust_chain_pem =~ "BEGIN CERTIFICATE"
      assert result.fingerprints == [ca.fingerprint]
      refute Map.has_key?(result, :crl_url)
    end

    test "includes :crl_url when provided", %{ca: ca} do
      result = Sources.trust_chain([ca], crl_url: "https://crl.example/root.crl")

      assert result.crl_url == "https://crl.example/root.crl"
    end

    test "empty chain → empty PEM and empty fingerprints" do
      assert Sources.trust_chain([]) == %{trust_chain_pem: "", fingerprints: []}
    end
  end
end
