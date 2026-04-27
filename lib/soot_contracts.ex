defmodule SootContracts do
  @moduledoc """
  Contract bundles: the device's read-only view of what the backend
  declares.

  A bundle is a versioned, signed collection of JSON manifests + binary
  assets. Devices fetch it over mTLS at `/.well-known/soot/contract` and
  use it to configure their MQTT subscriptions, validate telemetry
  schemas, and pin the CA chain.

  See:

    * `SootContracts.Bundle.assemble/1` — build a bundle from registered
      ash_mqtt resources and soot_telemetry stream modules.
    * `SootContracts.Bundle.sign/2` — sign the manifest using an
      `AshPki.CertificateAuthority`.
    * `SootContracts.Plug.WellKnown` — serve the current bundle.
    * `SootContracts.Diff.between/2` — structured diff between two
      bundles.

  ## Resource overrides

  `BundleRow` ships as an `Ash.Resource` extension under
  `SootContracts.Resource.BundleRow` plus a thin `Ash.DataLayer.Ets`
  default at `SootContracts.BundleRow`. Production deployments override
  with their own AshPostgres-backed module and register via
  `config :soot_contracts, bundle_row: MyApp.BundleRow`.
  """

  @doc "Configured `BundleRow` resource module."
  @spec bundle_row() :: module()
  def bundle_row,
    do: Application.get_env(:soot_contracts, :bundle_row, SootContracts.BundleRow)
end
