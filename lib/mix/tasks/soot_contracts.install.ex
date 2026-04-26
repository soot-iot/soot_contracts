defmodule Mix.Tasks.SootContracts.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs the Soot contracts bundle generator into a Phoenix project"
  end

  def example do
    "mix igniter.install soot_contracts"
  end

  def long_doc do
    """
    #{short_doc()}

    Generates an empty `Contracts` Ash domain in the operator's
    project, creates the `priv/contracts/` output directory used by
    the bundle generator, configures the contract-signing key path,
    and imports the `soot_contracts` formatter rules. Composed by
    `mix soot.install`; can also be run standalone.

    See the `UI-SPEC.md` in the `soot` package for the full design.

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
      |> create_contracts_domain()
      |> create_contracts_output_dir()
      |> configure_signing_key_path()
      |> note_next_steps()
    end

    defp create_contracts_domain(igniter) do
      module = Igniter.Project.Module.module_name(igniter, "Contracts")

      Igniter.Project.Module.create_module(
        igniter,
        module,
        """
        @moduledoc \"\"\"
        Ash domain for the operator's contract bundle bookkeeping.

        `soot_contracts` does not require any user-facing Ash
        resources; this module exists so the bundle generator has a
        well-known domain to register helpers under and so operators
        have an obvious extension point if they want to model their
        own contract metadata as Ash resources.

        The framework does not re-touch this file once generated.
        \"\"\"

        use Ash.Domain

        resources do
        end
        """
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

    defp configure_signing_key_path(igniter) do
      Igniter.Project.Config.configure(
        igniter,
        "config.exs",
        :soot_contracts,
        [:signing_key_path],
        "priv/pki/contract_signing_key.pem"
      )
    end

    defp note_next_steps(igniter) do
      Igniter.add_notice(igniter, """
      soot_contracts installed.

      Next steps:

        mix soot.contracts.build   # render and sign a contract bundle

      Generated bundles land in `priv/contracts/`. The signing key is
      read from `config :soot_contracts, :signing_key_path` (defaults
      to `priv/pki/contract_signing_key.pem`); `ash_pki` provisions
      that key during `mix ash.setup` if it is missing.

      The `Contracts` domain in `lib/<app>/contracts.ex` is the
      operator-owned extension point — add Ash resources there if you
      want to model contract metadata in your own database.
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
