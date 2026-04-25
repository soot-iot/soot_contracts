# `soot_contracts` — Phase 6 quality review

Reviewed against `sprawl/soot/QUALITY-REVIEW.md` at commit `4c3f882`.
Findings ordered by severity within each group.

## Gate status (before review)

```
mix deps.unlock --check-unused   ✗ until `mix deps.get` is run; clean after
mix deps.audit                   ✗ task not found (mix_audit not installed)
mix format --check-formatted     ✗ bundle_test.exs, diff_test.exs,
                                   canonical_json.ex dirty
mix compile --warnings-as-errors ✓
mix credo --strict               ✗ task not found
mix sobelow                      ✗ task not found
mix test                         ✓ 41 tests, 0 failures
mix dialyzer                     ✗ task not found
```

## Correctness bugs

### 1. `Bundle.verify/2` crashes on a non-base64 signature
`decode_signature/1` for a binary returns `Base.decode64(b64)`, which
gives `{:ok, bin} | :error`. The bare `:error` atom matches neither
`{:ok, _}` (the with-clause) nor any of the `else` branches
(`false -> ...` and `{:error, _} -> err`). Result: a tampered manifest
whose `signature` field has been replaced with arbitrary garbage raises
`WithClauseError` instead of returning `{:error, :invalid_signature}`.
Fix: normalise `:error` → `{:error, :invalid_signature}` in
`decode_signature/1`, or add an `:error -> {:error, :invalid_signature}`
clause to the `else`.

Reference: `lib/soot_contracts/bundle.ex:97-108`, `:211-212`.

### 2. `BundleRow` lifecycle says retired bundles "should no longer be served" but the plug serves them
`BundleRow`'s moduledoc states `:retired` is "kept for audit only".
`Plug.WellKnown.serve_manifest/2` and `serve_asset/3` go through
`BundleRow.get_by_fingerprint/1`, whose action only filters on
`fingerprint == ^arg`. A retired bundle is therefore returned and served
identically to a `:current` or `:superseded` one. Either tighten the
plug to `404` retired bundles, or update the moduledoc to reflect that
retired is purely a marker (not enforced at serve time).

References: `lib/soot_contracts/bundle_row.ex:9-13`,
`lib/soot_contracts/plug/well_known.ex:79-97`.

### 3. `Publisher.next_version/0` swallows `Ash.read` failures
```elixir
case Ash.read(BundleRow, ...) do
  {:ok, []} -> 1
  {:ok, rows} -> max + 1
  _ -> 1
end
```
The catch-all `_ -> 1` collapses a transient read error into "first
publish". If the read fails after a real row already exists, the next
publish would write `version: 1` which then collides with the existing
identity-distinct row. Either let the error propagate or pattern-match
explicitly on `{:error, _}` and surface it.

Reference: `lib/soot_contracts/publisher.ex:55-61`.

### 4. README's `Plug.Builder.compile` example is not a real API
```elixir
forward "/.well-known/soot/contract",
  to: Plug.Builder.compile([...])
```
`Plug.Builder.compile/3` is an internal compilation helper, not a
runtime constructor. Operators following the README will get
`UndefinedFunctionError` or argument errors. Replace with the standard
pattern (a wrapper module that `use Plug.Builder` and pipelines mTLS +
the WellKnown plug, or `Plug.Router.forward` directly to
`SootContracts.Plug.WellKnown` after running mTLS in an outer pipeline).

Reference: `README.md:88-95`.

### 5. `code_interface :create` arg list omits `signed_by_ca_id`
The default `:create` action accepts `signed_by_ca_id` (it's listed in
`defaults`), and `Publisher.publish!/2` does pass it through
`Ash.create/3`. But `code_interface` declares
`define :create, args: [:fingerprint, :version, :manifest, :assets]`,
so `BundleRow.create/4` ignores `signed_by_ca_id`. Today nothing calls
the code-interface `create`, but it's a foot-gun if a future caller
prefers the typed wrapper. Either add `:signed_by_ca_id` to the
`args:` list (or pass it via overrides) or drop the unused interface.

Reference: `lib/soot_contracts/bundle_row.ex:84-90`.

## Resource hygiene

### 6. Missing `belongs_to :signed_by_ca`
`BundleRow.signed_by_ca_id` is a bare uuid attribute. `ash_pki` is a
direct dependency, so the relationship can be wired:

```elixir
relationships do
  belongs_to :signed_by_ca, AshPki.CertificateAuthority,
    attribute_writable?: true,
    public?: true
end
```

Same shape as the gap soot_telemetry reported. Wiring it lets policies,
Cinder, and the future paper-trail integration follow the link.

Reference: `lib/soot_contracts/bundle_row.ex:35`.

### 7. `Domain` uses `validate_config_inclusion?: false` without a comment
A surprising opt-out. Same finding as soot_telemetry; either explain
why ("library may be loaded into hosts that don't list it in
`:ash_domains`") or drop it.

Reference: `lib/soot_contracts/domain.ex:3`.

### 8. `Sources.@compile {:no_warn_undefined, [Resource]}` is a leftover
`AshMqtt.Resource` (the bare module) is *aliased* in `Sources` but
never called. The compile attribute and its comment ("Hint for
compile-time pruning; ensures the deps are linked even when only one
path is exercised at runtime") describe behaviour `@compile :no_warn_undefined`
doesn't actually have — it just suppresses warnings. Remove `Resource`
from the alias and drop the `@compile` directive.

Reference: `lib/soot_contracts/sources.ex:19, 155`.

## Test gaps

### 9. `SootContracts.Sources` has no direct tests
Every helper (`topics/1`, `commands/1`, `shadows/1`, `streams/1`,
`trust_chain/2` and the descriptor builders) is exercised only
indirectly via `Bundle.assemble/1`. Add a focused test module covering
each public function — at minimum the empty-input edge cases (`[]`
inputs → empty maps, `crl_url: nil` → no `:crl_url` key) and the
descriptor shapes per resource type.

### 10. `BundleRow.retire` action is never tested
`update :supersede` is exercised via `Publisher.publish!/2`. `retire`
is dead-on-arrival — no test calls it, and there's no production caller
yet. Either add a direct resource test (`:current → :retired`,
`:superseded → :retired`) or remove the action until something needs it.

Reference: `lib/soot_contracts/bundle_row.ex:65-69`.

### 11. `Bundle.verify/2` branches not covered
* `:extraneous_asset` — assets blob has a path not present in the
  manifest index. No test.
* `:invalid_signature` from a tampered manifest body (e.g. mutating
  `:fingerprint` or `:generated_at` on a signed bundle). The current
  manifest-tamper test mutates `:size` inside the assets index, which
  short-circuits via `verify_assets/1` rather than the signature
  check.
* Garbage base64 in `signature` — see Bug 1.
* Bad PEM in `public_key_for/1` (`X509.Certificate.from_pem/1`
  returning an error) — no test.

### 12. `Bundle.sign/2` non-Software key strategy raise not tested
`sign_body/2` raises `ArgumentError` on any non-`Software` strategy.
Not asserted; future strategies need this guard to fail loudly until
they're wired up.

Reference: `lib/soot_contracts/bundle.ex:199-209`.

### 13. `Diff.between/2` `BundleRow` argument shape not tested
`normalise/1` has three clauses: `nil`, `%BundleRow{}`, and the
in-memory bundle map. Tests cover `nil` and the in-memory map. The
`BundleRow` clause — the one operators hit when running
`mix soot.contracts.diff` — has no direct test (the mix-task test
exercises it through `summarise/1`, not `Diff.between/2`).

### 14. `Publisher.current/0` failure path not tested
`Publisher.current` swallows `{:error, _}` into `nil`. Today the only
way this triggers is `BundleRow.current` failing on the underlying
read. Cheap to assert via a separate read action with a mocked failure
or, more pragmatically, document that `nil` covers both "no current
bundle" and "read failed".

### 15. Plug never tested against a `:retired` row
Tied to Bug 2 — pick a behaviour and add the corresponding assertion.

### 16. `test_helper.exs` doesn't enable `capture_log: true`
A plain `ExUnit.start()`. Test output is fine today (no logger calls
from the lib), but soot_telemetry's review settled on
`capture_log: true` as the floor for new libraries.

## Tooling gaps

### 17. No `LICENSE` file
`package: licenses: ["MIT"]` is declared but no LICENSE file ships.

### 18. Hex package metadata incomplete
* `links: %{}` — empty map. Add at least `"GitHub" => @source_url`.
* No `files:` allow-list. Defaults pull in `_build/`, `priv/contracts/`,
  etc.
* No `source_url`, `docs:`, `aliases:` — same shape as the
  finalised `soot_telemetry/mix.exs`.

Reference: `mix.exs:30-36`.

### 19. `consolidate_protocols: Mix.env() != :test`
Should be `Mix.env() == :prod`. Same playbook finding as soot_core /
soot_telemetry.

Reference: `mix.exs:13`.

### 20. `extra_applications: [:logger, :crypto, :public_key]`
`:public_key` already pulls `:crypto`. Drop `:crypto`.

Reference: `mix.exs:22`.

### 21. No `.tool-versions`
Pin `elixir 1.18.3-otp-27` / `erlang 27.3` to keep CI and local in
sync — same pin used in the rest of the stack.

### 22. No `CHANGELOG.md`
Mirror `soot_telemetry/CHANGELOG.md`. First entry: "Initial Phase 6
release".

### 23. No CI workflow
Mirror `soot_telemetry/.github/workflows/elixir.yml` — same gate
steps.

### 24. No lint stack
No `.credo.exs`, no `.dialyzer_ignore.exs`, no `.sobelow-conf`. No
deps for `:credo`, `:dialyxir`, `:sobelow`, `:mix_audit`, `:ex_doc`.

## Stylistic / minor

### 25. Formatter dirty
* `test/soot_contracts/bundle_test.exs` — multi-line `Bundle.assemble`
  calls indented inline (formatter wants the assignment on its own
  line).
* `test/soot_contracts/diff_test.exs` — same shape; also redundant
  parens around `Enum.map(...)` in `... in (Enum.map(...))`.
* `lib/soot_contracts/canonical_json.ex` — line 34 over the 98-char
  limit; the formatter rewrites it as a do-clause.

### 26. README claims "41 tests"
Currently true, but a hand-maintained number drifts. Drop the count or
replace with "see `mix test`".

Reference: `README.md:145-146`.

### 27. `Bundle.compute_fingerprint/1` docstring describes a
non-existent use-case
"Re-fingerprint a bundle. Used after an external mutation to detect
whether the assets have changed." — only `assemble/1` calls this and
nothing in lib re-fingerprints externally. Either drop the
"after an external mutation" framing or remove the public spec.

Reference: `lib/soot_contracts/bundle.ex:131-141`.

### 28. Mix task `load_module/1` error UX
`Code.ensure_loaded!` raises a generic message. Mirror the
soot_telemetry finding: `Mix.raise/1` with "could not load `<name>` —
make sure it's compiled and reachable from this project".

Reference: `lib/mix/tasks/soot.contracts.build.ex:65-69`.

### 29. `Mix.Tasks.Soot.Contracts.Diff.resolve/2` duplicated per key
Two near-identical clauses for `:before` and `:after`. Collapse to one
function that takes the key.

Reference: `lib/mix/tasks/soot.contracts.diff.ex:37-49`.

### 30. `Sources.streams/1` builds a descriptor with `name:` as an atom
inside the map but `Atom.to_string` on the outer key. The descriptor
goes through `CanonicalJSON.encode_pretty!`, which atom-stringifies
correctly, but the asymmetry (string outer key, atom inner key) is a
small surprise. Consider stringifying `:name` for consistency, or note
the shape.

Reference: `lib/soot_contracts/sources.ex:62-74`.
