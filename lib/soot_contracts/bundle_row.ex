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
    authorizers: [Ash.Policy.Authorizer],
    extensions: [SootContracts.Resource.BundleRow]

  ets do
    private? false
  end

  # Default policies (POLICY-SPEC §4.1). `:publisher` covers the
  # internal publishing flow (fingerprint lookup, current,
  # supersession, create). `:public_reader` covers the well-known
  # bundle lookup at `/.well-known/soot/contract/...` and the
  # `mix soot.contracts.diff` task.
  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy always() do
      access_type :strict
      authorize_if actor_attribute_equals(:part, :publisher)
      authorize_if actor_attribute_equals(:part, :public_reader)
    end
  end
end
