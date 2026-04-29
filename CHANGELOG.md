# Changelog

All notable changes to `soot_contracts` are documented here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project adheres to semantic versioning.

## [Unreleased]

### Added
- `mix soot_contracts.install` now generates an AshPostgres-backed
  consumer `BundleRow` resource module under `lib/<app>/bundle_row.ex`
  and registers it in `config/config.exs` under
  `:soot_contracts, bundle_row:`. The installer composes
  `ash_postgres.install` to wire the consumer's Repo and the
  `:ash_postgres` dep. The library's own concrete default stays on
  `Ash.DataLayer.Ets` for the soot_contracts test suite; consumer
  projects always boot against AshPostgres, which is mandatory in the
  soot stack.
- `BundleRow` belongs_to `signed_by_ca` relationship (was a bare uuid).
- Direct resource tests for `BundleRow` covering create, supersede,
  retire, lookups, and the unique-fingerprint identity.
- Direct tests for `SootContracts.Sources` (topics, commands, shadows,
  streams, trust_chain).
- `Bundle.verify` coverage for `:invalid_signature` (garbage base64),
  `:extraneous_asset`, manifest-body tampering, and the non-Software
  key-strategy raise.
- `Diff.between/2` coverage for `BundleRow` arguments.
- `Plug.WellKnown` 404s retired bundles.

### Changed
- `Bundle.verify` returns `{:error, :invalid_signature}` on a non-base64
  `signature` field instead of raising `WithClauseError`.
- `Publisher.next_version/0` raises on read errors instead of silently
  returning `1` (which would collide on the existing identity).
- README's mounting example replaced with a `Plug.Builder` wrapper —
  `Plug.Builder.compile/3` is not a public runtime API.
- `BundleRow.create` code interface accepts `signed_by_ca_id`.

## [0.1.0] - 2026-04-26

### Added
- Initial Phase 6 release: contract bundle assembly, canonical-JSON
  encoding, sign/verify against an `AshPki.CertificateAuthority`,
  `Publisher.publish!/2` with idempotent fingerprinting + supersession,
  `Plug.WellKnown` serving the bundle at `/.well-known/soot/contract`,
  `Diff.between/2` over manifests, and the `mix soot.contracts.build`
  / `mix soot.contracts.diff` tasks.
