defmodule SootContracts.MixTasksTest do
  use ExUnit.Case, async: false

  alias SootContracts.{Bundle, Publisher}
  alias SootContracts.Test.Fixtures.{Device, DeviceShadow, Vibration}
  alias SootContracts.Test.Helpers

  @tmp Path.join(System.tmp_dir!(), "soot_contracts_mix_test")

  setup do
    File.rm_rf!(@tmp)
    File.mkdir_p!(@tmp)
    Helpers.reset_ets!()
    on_exit(fn -> File.rm_rf!(@tmp) end)
    {:ok, ca: Helpers.fresh_ca!()}
  end

  describe "mix soot.contracts.build" do
    test "publishes the bundle and writes assets to disk", %{ca: ca} do
      out = Path.join(@tmp, "current")

      Mix.Tasks.Soot.Contracts.Build.run([
        "--signing-ca",
        ca.name,
        "--mqtt",
        "SootContracts.Test.Fixtures.Device",
        "--mqtt",
        "SootContracts.Test.Fixtures.DeviceShadow",
        "--stream",
        "SootContracts.Test.Fixtures.Vibration",
        "--out",
        out
      ])

      assert Publisher.current() != nil
      assert File.exists?(Path.join(out, "manifest.json"))
      assert File.exists?(Path.join(out, "topics.json"))
      assert File.exists?(Path.join(out, "streams/vibration.json"))
      assert File.exists?(Path.join(out, "pki/trust_chain.pem"))
    end

    test "without --out, only persists in-DB", %{ca: ca} do
      Mix.Tasks.Soot.Contracts.Build.run([
        "--signing-ca",
        ca.name,
        "--mqtt",
        "SootContracts.Test.Fixtures.Device"
      ])

      assert Publisher.current() != nil
    end
  end

  describe "mix soot.contracts.diff" do
    test "prints structured JSON of the diff", %{ca: ca} do
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
          mqtt_resources: [Device, DeviceShadow],
          telemetry_streams: [Vibration],
          trust_chain: [ca],
          generated_at: ~U[2026-04-26 13:00:00Z]
        )
        |> Bundle.sign(ca)
        |> Publisher.publish!(ca)

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Soot.Contracts.Diff.run([
            "--before",
            first.fingerprint,
            "--after",
            second.fingerprint
          ])
        end)

      decoded = Jason.decode!(output)

      assert decoded["before"] == first.fingerprint
      assert decoded["after"] == second.fingerprint
      assert "streams/vibration.json" in decoded["added"]
      assert "topics.json" in decoded["changed"]
    end

    test "errors out on unknown fingerprint", %{ca: ca} do
      _ = ca

      ExUnit.CaptureIO.capture_io(fn ->
        assert_raise Mix.Error, fn ->
          Mix.Tasks.Soot.Contracts.Diff.run(["--before", "abc123"])
        end
      end)
    end
  end
end
