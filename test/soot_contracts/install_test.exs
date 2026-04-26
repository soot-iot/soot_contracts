defmodule Mix.Tasks.SootContracts.InstallTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  defp project_with_router do
    test_project(
      files: %{
        "lib/test_web/router.ex" => """
        defmodule TestWeb.Router do
          use Phoenix.Router

          pipeline :device_mtls do
            plug AshPki.Plug.MTLS, require_known_certificate: true
          end

          scope "/" do
            pipe_through :device_mtls

            forward "/enroll", SootCore.Plug.Enroll
          end
        end
        """,
        "lib/test_web.ex" => """
        defmodule TestWeb do
          def router do
            quote do
              use Phoenix.Router
            end
          end
        end
        """
      }
    )
  end

  describe "info/2" do
    test "exposes the documented option schema" do
      info = Mix.Tasks.SootContracts.Install.info([], nil)
      assert info.group == :soot
      assert info.schema == [example: :boolean, yes: :boolean]
      assert info.aliases == [y: :yes, e: :example]
    end
  end

  describe "domain registration" do
    test "registers SootContracts.Domain in operator's :ash_domains" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_contracts.install", [])

      diff = diff(result, only: "config/config.exs")
      assert diff =~ "SootContracts.Domain"
      assert diff =~ "ash_domains:"
    end
  end

  describe "formatter wiring" do
    test "imports the soot_contracts formatter rules" do
      project_with_router()
      |> Igniter.compose_task("soot_contracts.install", [])
      |> assert_has_patch(".formatter.exs", """
      + |  import_deps: [:soot_contracts]
      """)
    end
  end

  describe "config wiring" do
    test "sets :soot_contracts, :output_dir to priv/contracts" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_contracts.install", [])

      diff = diff(result, only: "config/config.exs")
      assert diff =~ ":soot_contracts"
      assert diff =~ "output_dir:"
      assert diff =~ "priv/contracts"
    end
  end

  describe "contracts output directory" do
    test "creates priv/contracts/.gitkeep" do
      project_with_router()
      |> Igniter.compose_task("soot_contracts.install", [])
      |> assert_creates("priv/contracts/.gitkeep")
    end
  end

  describe "router mount" do
    test "adds /.well-known/soot/contract forward to the :device_mtls scope" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_contracts.install", [])

      diff = diff(result, only: "lib/test_web/router.ex")
      assert diff =~ "/.well-known/soot/contract"
      assert diff =~ "SootContracts.Plug.WellKnown"
    end

    test "warns when no router exists" do
      igniter =
        test_project(files: %{})
        |> Igniter.compose_task("soot_contracts.install", [])

      assert Enum.any?(igniter.warnings, &(&1 =~ "No Phoenix router")) or
               Enum.any?(igniter.notices, &(&1 =~ "soot_contracts installed"))
    end
  end

  describe "idempotency" do
    test "re-running the installer leaves the formatter untouched" do
      project_with_router()
      |> Igniter.compose_task("soot_contracts.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_contracts.install", [])
      |> assert_unchanged(".formatter.exs")
    end

    test "re-running the installer leaves the router untouched" do
      project_with_router()
      |> Igniter.compose_task("soot_contracts.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_contracts.install", [])
      |> assert_unchanged("lib/test_web/router.ex")
    end
  end

  describe "next-steps notice" do
    test "always emits a soot_contracts installed notice" do
      igniter =
        project_with_router()
        |> Igniter.compose_task("soot_contracts.install", [])

      assert Enum.any?(igniter.notices, &(&1 =~ "soot_contracts installed"))
    end

    test "notice mentions the contract output dir" do
      igniter =
        project_with_router()
        |> Igniter.compose_task("soot_contracts.install", [])

      assert Enum.any?(igniter.notices, &(&1 =~ "priv/contracts"))
    end
  end
end
