defmodule SootContracts.Resource.BundleRow do
  @moduledoc """
  `Ash.Resource` extension that injects the `SootContracts` bundle-row
  schema into a consumer-owned resource module.

  Usage and override semantics mirror `SootCore.Resource.Tenant`. The
  `:signed_by_ca` relationship points at the configured `CertificateAuthority`
  resource module — override via the `soot_contracts` DSL section:

      soot_contracts do
        certificate_authority MyApp.CertificateAuthority
      end

  Then register via `config :soot_contracts, bundle_row: MyApp.BundleRow`.
  """

  @soot_contracts %Spark.Dsl.Section{
    name: :soot_contracts,
    describe: """
    Sibling-resource references for this BundleRow resource.
    """,
    schema: [
      certificate_authority: [
        type: :atom,
        default: AshPki.CertificateAuthority,
        doc: "The `CertificateAuthority` resource that signs bundles."
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@soot_contracts],
    transformers: [SootContracts.Resource.BundleRow.Transformers.Inject]
end
