defmodule SootContracts.BundleRow do
  @moduledoc """
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
  """

  use Ash.Resource,
    otp_app: :soot_contracts,
    domain: SootContracts.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? false
  end

  attributes do
    uuid_primary_key :id

    attribute :fingerprint, :string, allow_nil?: false, public?: true
    attribute :version, :integer, allow_nil?: false, default: 1, public?: true
    attribute :manifest, :map, allow_nil?: false, public?: true
    attribute :assets, :map, allow_nil?: false, public?: true
    attribute :signed_by_ca_id, :uuid, public?: true

    attribute :status, :atom do
      constraints one_of: [:current, :superseded, :retired]
      default :current
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_fingerprint, [:fingerprint], pre_check_with: SootContracts.Domain
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:fingerprint, :version, :manifest, :assets, :signed_by_ca_id]
    ]

    update :supersede do
      accept []
      require_atomic? false
      change set_attribute(:status, :superseded)
    end

    update :retire do
      accept []
      require_atomic? false
      change set_attribute(:status, :retired)
    end

    read :get_by_fingerprint do
      argument :fingerprint, :string, allow_nil?: false
      get? true
      filter expr(fingerprint == ^arg(:fingerprint))
    end

    read :current do
      get? true
      filter expr(status == :current)
      prepare build(sort: [version: :desc])
    end
  end

  code_interface do
    define :create, args: [:fingerprint, :version, :manifest, :assets]
    define :supersede
    define :retire
    define :get_by_fingerprint, args: [:fingerprint]
    define :current
  end
end
