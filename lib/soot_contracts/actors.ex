defmodule SootContracts.Actors do
  @moduledoc """
  Actor factory for `soot_contracts`.

  System parts:

    * `:publisher` — internal bundle publishing flow
      (`SootContracts.Publisher`): fingerprint lookup, version
      computation, supersession, and the `BundleRow` create.

    * `:public_reader` — read-side path that backs the
      `/.well-known/contracts/...` endpoint and the
      `mix soot.contracts.diff` task. Public-facing reads of the
      published bundle metadata; never modifies state.

  See umbrella `soot/POLICY-SPEC.md` for the cross-library actor
  contract.
  """

  alias SootContracts.Actors.System

  @type system_part :: System.part()

  @doc "Build a `System` actor for an internal subsystem."
  @spec system(system_part()) :: System.t()
  def system(part) when is_atom(part), do: %System{part: part}

  @spec system(system_part(), keyword() | binary() | nil) :: System.t()
  def system(part, tenant_id) when is_atom(part) and is_binary(tenant_id),
    do: %System{part: part, tenant_id: tenant_id}

  def system(part, nil) when is_atom(part), do: %System{part: part}

  def system(part, opts) when is_atom(part) and is_list(opts),
    do: %System{part: part, tenant_id: Keyword.get(opts, :tenant_id)}
end
