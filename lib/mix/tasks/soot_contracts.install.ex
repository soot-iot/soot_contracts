defmodule Mix.Tasks.SootContracts.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs soot_contracts: registers domain, generates AshPostgres-backed BundleRow, wires /.well-known/soot/contract"
  end

  def example do
    "mix igniter.install soot_contracts"
  end

  def long_doc do
    """
    #{short_doc()}

    `SootContracts.Domain` ships its `BundleRow` resource as a concrete
    library module. The installer registers that domain in the
    operator's `:ash_domains` config rather than generating an empty
    stub copy of the library default.

    The library default runs on `Ash.DataLayer.Ets` so the
    soot_contracts test suite can run with zero infra, but Postgres is
    mandatory in the soot stack. The installer therefore composes
    `ash_postgres.install` (wiring the consumer's Repo + the
    `:ash_postgres` dep) and generates an AshPostgres-backed consumer
    resource module under `lib/<app>/`:

      * `<App>.BundleRow` — table `bundle_rows`

    The generated module applies the `SootContracts.Resource.BundleRow`
    extension and declares its `:signed_by_ca` target via the
    `soot_contracts do … end` block, defaulting to
    `<App>.CertificateAuthority` (which `mix ash_pki.install`
    generates earlier in the umbrella `mix soot.install` flow). The
    module is then registered in `config/config.exs` under
    `:soot_contracts, bundle_row:` so the rest of soot_contracts picks
    it up at boot. Operators own the generated file post-install —
    edit the `postgres do … end` block, add custom actions, etc. as
    needed.

    The installer also creates `priv/contracts/` (the bundle output
    directory used by `mix soot.contracts.build`), seeds the
    `:soot_contracts, :output_dir` config, and mounts
    `forward "/.well-known/soot/contract", SootContracts.Plug.WellKnown`
    inside the `:device_mtls` scope created by `soot_core.install`.

    Composed by `mix soot.install`; can also be run standalone.

    See `GENERATOR-SPEC.md` in the `soot` package for the full design.

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

      * `--example` — same shape as the rest of the Soot installers;
        currently a no-op for `soot_contracts` since the framework
        does not yet ship a sample contract bundle.
      * `--yes` — answer yes to dependency-fetching prompts.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.SootContracts.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"
    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :soot,
        example: __MODULE__.Docs.example(),
        only: nil,
        composes: ["ash_postgres.install"],
        schema: [example: :boolean, yes: :boolean],
        defaults: [example: false, yes: false],
        aliases: [y: :yes, e: :example]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.Project.Formatter.import_dep(:soot_contracts)
      |> register_domain()
      |> compose_ash_postgres()
      |> generate_consumer_resources()
      |> register_consumer_resources()
      |> configure_output_dir()
      |> create_contracts_output_dir()
      |> mount_well_known_route()
      |> note_next_steps()
    end

    defp register_domain(igniter) do
      app = Igniter.Project.Application.app_name(igniter)

      Igniter.Project.Config.configure(
        igniter,
        "config.exs",
        app,
        [:ash_domains],
        [SootContracts.Domain],
        updater: fn list ->
          Igniter.Code.List.prepend_new_to_list(list, SootContracts.Domain)
        end
      )
    end

    # `ash_postgres.install` handles the `:ash_postgres` dep, the Repo
    # module, the `:ecto_repos` config, and dev/test/runtime DB URLs.
    # Threading `--yes` through keeps the install non-interactive when
    # the parent installer is running with `-y`. The third-arg fallback
    # is a no-op so the installer's own test suite (which runs without
    # ash_postgres in deps) can still exercise the rest of the
    # pipeline; in real consumer projects `ash_postgres.install` is
    # available because the parent `mix igniter.install` resolves it.
    defp compose_ash_postgres(igniter) do
      argv = if igniter.args.options[:yes], do: ["--yes"], else: []
      Igniter.compose_task(igniter, "ash_postgres.install", argv, & &1)
    end

    defp generate_consumer_resources(igniter) do
      module = bundle_row_module(igniter)
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        repo = Igniter.Project.Module.module_name(igniter, "Repo")
        body = bundle_row_module_body(igniter, repo)
        Igniter.Project.Module.create_module(igniter, module, body)
      end
    end

    defp register_consumer_resources(igniter) do
      module = bundle_row_module(igniter)

      Igniter.Project.Config.configure(
        igniter,
        "config.exs",
        :soot_contracts,
        [:bundle_row],
        module
      )
    end

    defp bundle_row_module(igniter) do
      Igniter.Project.Module.module_name(igniter, "BundleRow")
    end

    defp bundle_row_module_body(igniter, repo) do
      module = bundle_row_module(igniter)
      certificate_authority = Igniter.Project.Module.module_name(igniter, "CertificateAuthority")

      """
      @moduledoc \"\"\"
      AshPostgres-backed `BundleRow` resource generated by
      `mix soot_contracts.install`. Operators own this file — edit the
      `postgres do … end` block, add domain-specific actions, etc. as
      needed. The schema (attributes, identities, lifecycle actions)
      comes from the `SootContracts.Resource.BundleRow` extension; the
      `:signed_by_ca` relationship target is wired via the
      `soot_contracts do … end` block. Registered via
      `config :soot_contracts, bundle_row: #{inspect(module)}`.
      \"\"\"

      use Ash.Resource,
        otp_app: :#{otp_app(igniter)},
        domain: SootContracts.Domain,
        data_layer: AshPostgres.DataLayer,
        extensions: [SootContracts.Resource.BundleRow]

      postgres do
        table "bundle_rows"
        repo #{inspect(repo)}
      end

      soot_contracts do
        certificate_authority #{inspect(certificate_authority)}
      end
      """
    end

    defp otp_app(igniter), do: Igniter.Project.Application.app_name(igniter)

    defp configure_output_dir(igniter) do
      Igniter.Project.Config.configure(
        igniter,
        "config.exs",
        :soot_contracts,
        [:output_dir],
        "priv/contracts"
      )
    end

    defp create_contracts_output_dir(igniter) do
      Igniter.create_new_file(
        igniter,
        "priv/contracts/.gitkeep",
        "",
        on_exists: :skip
      )
    end

    # Adds `forward "/.well-known/soot/contract", SootContracts.Plug.WellKnown`
    # inside the `:device_mtls` scope. Idempotent: detects an existing
    # forward to SootContracts.Plug.WellKnown and leaves the router
    # alone if found.
    defp mount_well_known_route(igniter) do
      {igniter, router} =
        Igniter.Libs.Phoenix.select_router(
          igniter,
          "Which Phoenix router should the /.well-known/soot/contract endpoint be mounted in?"
        )

      cond do
        router == nil ->
          Igniter.add_warning(igniter, """
          No Phoenix router found. The /.well-known/soot/contract
          device-facing endpoint was not mounted. After your router is
          set up, re-run `mix igniter.install soot_contracts`.
          """)

        well_known_route_present?(igniter, router) ->
          igniter

        true ->
          Igniter.Libs.Phoenix.append_to_scope(
            igniter,
            "/",
            ~s|forward "/.well-known/soot/contract", SootContracts.Plug.WellKnown|,
            router: router,
            with_pipelines: [:device_mtls]
          )
      end
    end

    defp well_known_route_present?(igniter, router) do
      {_, _source, zipper} = Igniter.Project.Module.find_module!(igniter, router)

      case Igniter.Code.Common.move_to(zipper, fn z ->
             Igniter.Code.Function.function_call?(z, :forward, 2) and
               Igniter.Code.Function.argument_equals?(z, 1, SootContracts.Plug.WellKnown)
           end) do
        {:ok, _} -> true
        :error -> false
      end
    end

    defp note_next_steps(igniter) do
      Igniter.add_notice(igniter, """
      soot_contracts installed.

      `SootContracts.Domain` is registered in `:ash_domains`. The
      AshPostgres-backed `BundleRow` consumer resource has been
      generated under `lib/<app>/bundle_row.ex` and registered in
      `config/config.exs` under `:soot_contracts, bundle_row:`. The
      Repo module and `:ash_postgres` dep were wired by the composed
      `ash_postgres.install`.

      Operators own the generated resource file — edit
      `postgres do … end` block, add custom actions, etc. as needed.

      `/.well-known/soot/contract` is mounted under the `:device_mtls`
      pipeline.

      Generated bundles land in `priv/contracts/` (configured via
      `:soot_contracts, :output_dir`).

      Next steps:

        mix ash.codegen --name install_soot_contracts
        mix ash.setup
        mix soot.contracts.build   # render and sign a contract bundle
      """)
    end
  end
else
  defmodule Mix.Tasks.SootContracts.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"
    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task `soot_contracts.install` requires igniter. Add
      `{:igniter, "~> 0.6"}` to your project deps and try again, or
      invoke via:

          mix igniter.install soot_contracts

      For more information, see https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
