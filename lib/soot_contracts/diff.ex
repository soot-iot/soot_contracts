defmodule SootContracts.Diff do
  @moduledoc """
  Structured diff between two bundles.

      %{
        before: "<fingerprint-or-nil>",
        after:  "<fingerprint-or-nil>",
        added:   ["<path>", ...],
        removed: ["<path>", ...],
        changed: [%{path: "<path>", before: <body>, after: <body>}]
      }

  Both arguments may be either an in-memory bundle (`Bundle.assemble/1`
  output) or a `BundleRow` record (or `nil` for "no previous").
  """

  @doc "Compare two bundles. Argument order is `before, after`."
  @spec between(map() | struct() | nil, map() | struct() | nil) :: map()
  def between(before_arg, after_arg) do
    {before_assets, before_fp} = normalise(before_arg)
    {after_assets, after_fp} = normalise(after_arg)

    before_paths = MapSet.new(Map.keys(before_assets))
    after_paths = MapSet.new(Map.keys(after_assets))

    added =
      MapSet.difference(after_paths, before_paths)
      |> Enum.sort()

    removed =
      MapSet.difference(before_paths, after_paths)
      |> Enum.sort()

    changed =
      MapSet.intersection(before_paths, after_paths)
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        b = Map.get(before_assets, path)
        a = Map.get(after_assets, path)

        if b == a do
          []
        else
          [%{path: path, before: b, after: a}]
        end
      end)

    %{
      before: before_fp,
      after: after_fp,
      added: added,
      removed: removed,
      changed: changed
    }
  end

  defp normalise(nil), do: {%{}, nil}

  # In-memory bundle: %{manifest: %{fingerprint: ...}, assets: ...}.
  defp normalise(%{manifest: %{fingerprint: fp}, assets: assets}), do: {assets, fp}

  # BundleRow record (default or consumer override): top-level :assets
  # and :fingerprint. The pattern stays struct-shape-agnostic.
  defp normalise(%{assets: assets, fingerprint: fp}), do: {assets, fp}
end
