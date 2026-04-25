defmodule SootContracts.Publisher do
  @moduledoc """
  Persist an in-memory bundle as a `SootContracts.BundleRow`.

      bundle |> SootContracts.Bundle.sign(ca) |> SootContracts.Publisher.publish!(ca)

  - Inserts the new row with `status: :current`.
  - Marks the previous current row as `:superseded`.
  - Idempotent on fingerprint: a re-publish of the same fingerprint
    returns the existing row.
  """

  alias SootContracts.BundleRow

  @doc "Persist a bundle. The CA is the signer; its id is stamped into `signed_by_ca_id`."
  @spec publish!(map(), AshPki.CertificateAuthority.t()) :: BundleRow.t()
  def publish!(bundle, %AshPki.CertificateAuthority{} = ca) do
    fingerprint = bundle.manifest.fingerprint

    case BundleRow.get_by_fingerprint(fingerprint, authorize?: false) do
      {:ok, %BundleRow{} = existing} ->
        existing

      {:error, _} ->
        version = next_version()
        supersede_previous_current()

        {:ok, row} =
          Ash.create(
            BundleRow,
            %{
              fingerprint: fingerprint,
              version: version,
              manifest: bundle.manifest,
              assets: bundle.assets,
              signed_by_ca_id: ca.id
            },
            action: :create,
            authorize?: false
          )

        row
    end
  end

  @doc "The current bundle row or nil."
  @spec current() :: BundleRow.t() | nil
  def current do
    case BundleRow.current(authorize?: false) do
      {:ok, %BundleRow{} = row} -> row
      _ -> nil
    end
  end

  defp next_version do
    case Ash.read(BundleRow, authorize?: false) do
      {:ok, []} -> 1
      {:ok, rows} -> (Enum.map(rows, & &1.version) |> Enum.max()) + 1
      _ -> 1
    end
  end

  defp supersede_previous_current do
    case BundleRow.current(authorize?: false) do
      {:ok, %BundleRow{} = row} -> BundleRow.supersede(row, authorize?: false)
      _ -> :ok
    end
  end
end
