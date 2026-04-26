defmodule Mix.Tasks.SootContracts.InstallTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  describe "info/2" do
    test "exposes the documented option schema" do
      info = Mix.Tasks.SootContracts.Install.info([], nil)
      assert info.group == :soot
      assert info.schema == [example: :boolean, yes: :boolean]
      assert info.aliases == [y: :yes, e: :example]
    end
  end

  describe "generated files" do
    test "creates the Contracts domain module" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_contracts.install", [])
      |> assert_creates("lib/test/contracts.ex")
    end

    test "creates the priv/contracts/ output directory marker" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_contracts.install", [])
      |> assert_creates("priv/contracts/.gitkeep")
    end

    test "Contracts domain uses Ash.Domain with an empty resources block" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_contracts.install", [])

      diff = diff(result, only: "lib/test/contracts.ex")
      assert diff =~ "use Ash.Domain"
      assert diff =~ "resources do"
    end
  end

  describe "formatter wiring" do
    test "imports the soot_contracts formatter rules" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_contracts.install", [])
      |> assert_has_patch(".formatter.exs", """
      + |  import_deps: [:soot_contracts]
      """)
    end
  end

  describe "config wiring" do
    test "adds the contract signing key path to config.exs" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_contracts.install", [])

      diff = diff(result, only: "config/config.exs")
      assert diff =~ ":soot_contracts"
      assert diff =~ "signing_key_path"
      assert diff =~ "priv/pki/contract_signing_key.pem"
    end
  end

  describe "idempotency" do
    test "re-running the installer leaves the formatter untouched" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_contracts.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_contracts.install", [])
      |> assert_unchanged(".formatter.exs")
    end

    test "re-running the installer leaves the Contracts domain untouched" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_contracts.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_contracts.install", [])
      |> assert_unchanged("lib/test/contracts.ex")
    end
  end

  describe "next-steps notice" do
    test "always emits a soot_contracts installed notice" do
      igniter =
        test_project(files: %{})
        |> Igniter.compose_task("soot_contracts.install", [])

      assert Enum.any?(igniter.notices, &(&1 =~ "soot_contracts installed"))
      assert Enum.any?(igniter.notices, &(&1 =~ "mix soot.contracts.build"))
    end
  end
end
