defmodule Mix.Tasks.SootContracts.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs soot_contracts: registers domain, wires /.well-known/soot/contract"
  end

  def example do
    "mix igniter.install soot_contracts"
  end

  def long_doc do
    """
    #{short_doc()}

    `SootContracts.Domain` ships its `BundleRow` resource as a concrete
    library module. The installer registers that domain in the
    operator's `:ash_domains` config rather than generating empty
    copies.

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
        composes: [],
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

      `SootContracts.Domain` is registered in `:ash_domains`.
      `/.well-known/soot/contract` is mounted under the `:device_mtls`
      pipeline.

      Generated bundles land in `priv/contracts/` (configured via
      `:soot_contracts, :output_dir`).

      Next steps:

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
