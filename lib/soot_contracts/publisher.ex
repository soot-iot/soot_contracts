defmodule SootContracts.Publisher do
  @moduledoc """
  Persist an in-memory bundle as a `SootContracts.BundleRow`.

      bundle |> SootContracts.Bundle.sign(ca) |> SootContracts.Publisher.publish!(ca)

  - Inserts the new row with `status: :current`.
  - Marks the previous current row as `:superseded`.
  - Idempotent on fingerprint: a re-publish of the same fingerprint
    returns the existing row.

  The active `BundleRow` resource module is resolved through
  `SootContracts.bundle_row/0` so consumer overrides registered via
  `config :soot_contracts, bundle_row: MyApp.BundleRow` are honoured.
  """

  @doc "Persist a bundle. The CA is the signer; its id is stamped into `signed_by_ca_id`."
  @spec publish!(map(), AshPki.CertificateAuthority.t()) :: struct()
  def publish!(bundle, %AshPki.CertificateAuthority{} = ca) do
    bundle_row = SootContracts.bundle_row()
    fingerprint = bundle.manifest.fingerprint

    case bundle_row.get_by_fingerprint(fingerprint, actor: SootContracts.Actors.system(:publisher)) do
      {:ok, %_{} = existing} ->
        existing

      {:error, _} ->
        version = next_version()
        supersede_previous_current()

        {:ok, row} =
          Ash.create(
            bundle_row,
            %{
              fingerprint: fingerprint,
              version: version,
              manifest: bundle.manifest,
              assets: bundle.assets,
              signed_by_ca_id: ca.id
            },
            action: :create,
            actor: SootContracts.Actors.system(:publisher)
          )

        row
    end
  end

  @doc "The current bundle row or nil."
  @spec current() :: struct() | nil
  def current do
    case SootContracts.bundle_row().current(actor: SootContracts.Actors.system(:publisher)) do
      {:ok, %_{} = row} -> row
      _ -> nil
    end
  end

  defp next_version do
    case Ash.read(SootContracts.bundle_row(), actor: SootContracts.Actors.system(:publisher)) do
      {:ok, []} -> 1
      {:ok, rows} -> (Enum.map(rows, & &1.version) |> Enum.max()) + 1
      {:error, error} -> raise error
    end
  end

  defp supersede_previous_current do
    bundle_row = SootContracts.bundle_row()

    case bundle_row.current(actor: SootContracts.Actors.system(:publisher)) do
      {:ok, %_{} = row} -> bundle_row.supersede(row, actor: SootContracts.Actors.system(:publisher))
      {:error, _} -> :ok
    end
  end
end
