# `soot_contracts`

The contract bundle: a versioned, signed collection of JSON manifests
and binary assets that devices fetch over mTLS to learn what topics to
subscribe to, what schemas to upload, and which CAs to trust.

Depends on [`ash_pki`](../ash_pki) (signing keys), [`soot_core`](../soot_core),
[`ash_mqtt`](../ash_mqtt) (topic + shadow declarations), and
[`soot_telemetry`](../soot_telemetry) (stream schemas).

## Bundle shape

The assets array is fixed:

| path                              | contents                                                            |
|-----------------------------------|---------------------------------------------------------------------|
| `topics.json`                     | per-resource list of topic patterns + qos/retain/format/acl/dir     |
| `commands.json`                   | per-resource list of action declarations (topic, reply, timeout)    |
| `shadow.json`                     | per-resource shadow base + desired/reported attribute hints         |
| `streams/<name>.json`             | per-stream metadata (endpoint, retention, sequence field, fingerprint) |
| `streams/<name>.arrow_schema`     | canonical descriptor of the Arrow schema for `<name>`               |
| `pki/trust_chain.pem`             | CA chain devices should trust                                       |
| `pki/fingerprints.json`           | SHA-256 fingerprints of those CAs                                   |
| `pki/crl_url.txt`                 | (when configured) URL the device pulls the CRL from                 |

The manifest carries:

```json
{
  "version": 1,
  "generated_at": "<iso8601>",
  "fingerprint": "<sha256-hex>",
  "signed_by": "<signing-ca-fingerprint>",
  "signature": "<base64>",
  "assets": {
    "<path>": {"sha256": "<hex>", "size": <int>},
    ...
  }
}
```

## Determinism

Inputs render through `SootContracts.CanonicalJSON` (sorted map keys at
every level). Two bundles assembled from the same inputs produce
byte-identical assets and the same fingerprint regardless of insertion
order. The fingerprint is the SHA-256 of the canonical JSON of the
`manifest.assets` index, so it changes iff *any* asset's bytes change.

## Signing

`SootContracts.Bundle.sign/2` signs the manifest body (the manifest
minus the `signature` and `signed_by` fields) using the
`AshPki.CertificateAuthority`'s `KeyStrategy`. v0.1 supports
`Software` keys; HSM-backed signing falls under Phase 6 follow-ups in
`ash_pki` and slots in transparently when that lands.

`Bundle.verify/2` performs three checks:

1. each asset's bytes hash to the SHA-256 declared in the manifest
2. the manifest body verifies against the CA's public key
3. no asset blob is present that isn't in the manifest's index

Tampering at the asset-bytes layer or the manifest layer is rejected.

## Persistence + serving

`SootContracts.Publisher.publish!/2` persists a signed bundle as a
`SootContracts.BundleRow` (status `:current`), supersedes the previous
current row, and is idempotent on fingerprint. `BundleRow.assets` is a
`path → bytes` map so the well-known plug can serve historical
fingerprints.

`SootContracts.Plug.WellKnown` mounts at `/.well-known/soot/contract`:

```
GET /.well-known/soot/contract                    → 200 manifest of current bundle
GET /.well-known/soot/contract/<fingerprint>      → 200 manifest of that bundle
GET /.well-known/soot/contract/<fingerprint>/<asset-path>  → 200 asset bytes
```

ETag is the manifest fingerprint (or `<fingerprint>:<asset-path>` for
asset responses). `If-None-Match` returns `304`. Unknown fingerprint or
unknown asset → `404`. Non-`GET` → `405`.

In production, mount the plug behind `AshPki.Plug.MTLS` so only
authenticated devices can fetch contracts:

```elixir
defmodule MyApp.ContractsPipeline do
  use Plug.Builder

  plug AshPki.Plug.MTLS, require_known_certificate: true
  plug SootContracts.Plug.WellKnown
end

# in your router:
forward "/.well-known/soot/contract", to: MyApp.ContractsPipeline
```

## Diff

`SootContracts.Diff.between/2` returns:

```elixir
%{
  before: "<fingerprint-or-nil>",
  after:  "<fingerprint-or-nil>",
  added:   ["<path>", ...],
  removed: ["<path>", ...],
  changed: [%{path: "<path>", before: <body>, after: <body>}]
}
```

Both arguments may be a `Bundle.assemble/1` result, a `BundleRow`, or
`nil`.

## Mix tasks

```sh
mix soot.contracts.build \
      --signing-ca acme-root \
      --mqtt MyApp.Device --mqtt MyApp.Device.Shadow \
      --stream MyApp.Telemetry.Vibration \
      --crl-url https://crl.example.com/root.crl \
      [--out priv/contracts/current]

mix soot.contracts.diff \
      --before <fingerprint> \
      --after  <fingerprint>     # or omit --after to compare against current
```

## Out of scope (v0.1)

* HSM/PKCS#11 + KMS signing (interface in `ash_pki` is set up but
  implementations are deferred). The contract bundle's signing path
  composes against any future strategy unchanged.
* Real Arrow schema files. `streams/<name>.arrow_schema` is currently
  the canonical descriptor JSON; producing actual `.arrow` IPC
  schema files is a follow-up tied to wider Arrow IPC support.
* Asset compression / delta updates. Each bundle is shipped whole.

## Tests

```sh
mix test
```

Tests cover canonical JSON ordering + atom/datetime handling, bundle
assembly determinism, fingerprint sensitivity, sign/verify roundtrip
+ tampering rejection (both at the asset-bytes layer and the manifest
layer) + cross-CA verification rejection, publisher idempotence +
supersession, every plug branch (current manifest 200, historical
manifest 200, asset 200 with content-type, ETag/304 on both manifest
and asset, 404 unknown fingerprint, 404 unknown asset, 405 non-GET,
404 unmatched route), diff added/removed/changed branches across
two-arg combinations including `nil`, and both mix tasks end-to-end.
