defmodule Mix.Tasks.Soot.Contracts.Diff do
  @shortdoc "Diff two contract bundles and print a structured summary"

  @moduledoc """
  Print the diff between two persisted bundles.

      mix soot.contracts.diff --before <fingerprint> --after <fingerprint>
      mix soot.contracts.diff --after <fingerprint>          # vs. nothing
      mix soot.contracts.diff --before <fingerprint>         # vs. current

  When `--after` is omitted, the diff is taken against the current
  bundle. When `--before` is omitted, the diff is against an empty
  bundle (so every path appears in `:added`).

  Output is JSON-formatted to stdout; pipe through `jq`.
  """

  use Mix.Task

  alias SootContracts.{BundleRow, CanonicalJSON, Diff, Publisher}

  @switches [before: :string, after: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(args, strict: @switches)

    before_row = resolve(opts, :before)
    after_row = resolve(opts, :after) || Publisher.current()

    diff = Diff.between(before_row, after_row)

    Mix.shell().info(CanonicalJSON.encode_pretty!(summarise(diff)))
  end

  defp resolve(opts, key) do
    case Keyword.get(opts, key) do
      nil -> nil
      fp -> fetch!(fp)
    end
  end

  defp fetch!(fp) do
    case BundleRow.get_by_fingerprint(fp, authorize?: false) do
      {:ok, %BundleRow{} = row} -> row
      _ -> Mix.raise("no bundle with fingerprint #{fp}")
    end
  end

  defp summarise(diff) do
    %{
      before: diff.before,
      after: diff.after,
      added: diff.added,
      removed: diff.removed,
      changed: Enum.map(diff.changed, & &1.path)
    }
  end
end
