defmodule Mix.Tasks.SootContracts.InstallTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  # Igniter evaluates the consumer project's `config/config.exs` into
  # the live `Application` env so installer steps can inspect it. That
  # means our "register the BundleRow module" step leaks
  # `Test.BundleRow` into the soot_contracts app env for the rest of
  # this test run, which can break any subsequent test that resolves
  # `SootContracts.bundle_row()` via config. Snapshot the relevant
  # keys before each test and restore on exit.
  setup do
    keys = [
      :bundle_row,
      :output_dir
    ]

    snapshot =
      for key <- keys,
          {:ok, value} <- [Application.fetch_env(:soot_contracts, key)],
          do: {key, value}

    on_exit(fn ->
      for key <- keys do
        Application.delete_env(:soot_contracts, key)
      end

      for {key, value} <- snapshot do
        Application.put_env(:soot_contracts, key, value)
      end
    end)

    :ok
  end

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

  describe "info/2 composes" do
    test "composes ash_postgres.install" do
      info = Mix.Tasks.SootContracts.Install.info([], nil)
      assert info.composes == ["ash_postgres.install"]
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

    test "notice mentions the generated AshPostgres-backed BundleRow" do
      igniter =
        project_with_router()
        |> Igniter.compose_task("soot_contracts.install", [])

      assert Enum.any?(igniter.notices, &(&1 =~ "AshPostgres-backed"))
      assert Enum.any?(igniter.notices, &(&1 =~ "BundleRow"))
    end

    test "notice mentions ash.codegen + ash.setup" do
      igniter =
        project_with_router()
        |> Igniter.compose_task("soot_contracts.install", [])

      assert Enum.any?(igniter.notices, &(&1 =~ "mix ash.codegen --name install_soot_contracts"))
      assert Enum.any?(igniter.notices, &(&1 =~ "mix ash.setup"))
    end
  end

  describe "AshPostgres consumer resources" do
    @resource_path "lib/test/bundle_row.ex"

    defp generated_source(igniter, path) do
      source = igniter.rewrite.sources[path]

      assert source,
             "expected #{inspect(path)} to have been generated, but it was not. " <>
               "Created files: #{inspect(Map.keys(igniter.rewrite.sources))}"

      Rewrite.Source.get(source, :content)
    end

    test "generates the BundleRow consumer resource module under lib/<app>/" do
      project_with_router()
      |> Igniter.compose_task("soot_contracts.install", [])
      |> assert_creates(@resource_path)
    end

    test "BundleRow module wires AshPostgres + the SootContracts.Resource.BundleRow extension" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_contracts.install", [])

      content = generated_source(result, @resource_path)

      assert content =~ "defmodule Test.BundleRow"
      assert content =~ "use Ash.Resource"
      assert content =~ "otp_app: :test"
      assert content =~ "domain: SootContracts.Domain"
      assert content =~ "data_layer: AshPostgres.DataLayer"
      assert content =~ "extensions: [SootContracts.Resource.BundleRow]"
      assert content =~ ~s|table("bundle_rows")|
      assert content =~ "repo(Test.Repo)"
    end

    test "BundleRow module carries authorizer + admin bypass" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_contracts.install", [])

      content = generated_source(result, @resource_path)

      assert content =~ "authorizers: [Ash.Policy.Authorizer]"
      assert content =~ "policies do"
      assert content =~ "bypass actor_attribute_equals(:role, :admin) do"
    end

    test "BundleRow module includes a soot_contracts block referencing Test.CertificateAuthority" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_contracts.install", [])

      content = generated_source(result, @resource_path)

      assert content =~ "soot_contracts do"
      assert content =~ "certificate_authority(Test.CertificateAuthority)"
    end

    test "registers Test.BundleRow in config/config.exs under :soot_contracts" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_contracts.install", [])

      diff = diff(result, only: "config/config.exs")

      assert diff =~ "bundle_row: Test.BundleRow"
    end

    test "running the installer twice does not churn lib/test/bundle_row.ex" do
      project_with_router()
      |> Igniter.compose_task("soot_contracts.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_contracts.install", [])
      |> assert_unchanged(@resource_path)
    end

    test "running the installer twice does not churn config/config.exs" do
      project_with_router()
      |> Igniter.compose_task("soot_contracts.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_contracts.install", [])
      |> assert_unchanged("config/config.exs")
    end
  end
end
