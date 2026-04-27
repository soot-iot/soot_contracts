defmodule SootContracts.BundleRow do
  @moduledoc """
  Default `BundleRow` resource shipped with `soot_contracts`.

  An audit / serving row for a published contract bundle.

  Stores both the signed manifest (as a map) and the raw asset blobs
  (as a path → binary map) so the well-known plug can serve any
  historical fingerprint a device asks for.

  Lifecycle:

  - `:current` — the manifest served at `/.well-known/soot/contract`.
  - `:superseded` — older bundle, still queryable by fingerprint.
  - `:retired` — should no longer be served; kept for audit only.

  Naming: `BundleRow` to leave `SootContracts.Bundle` as the module
  that assembles + signs (in-memory) bundles.

  The schema is provided by the `SootContracts.Resource.BundleRow`
  extension. This default uses `Ash.DataLayer.Ets`; production
  deployments override with their own resource module backed by
  `AshPostgres.DataLayer` and register it via
  `config :soot_contracts, bundle_row: MyApp.BundleRow`.
  """

  use Ash.Resource,
    otp_app: :soot_contracts,
    domain: SootContracts.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [SootContracts.Resource.BundleRow]

  ets do
    private? false
  end
end
