defmodule SootContracts.PoliciesTest do
  @moduledoc """
  Boundary tests for the default `policies` block on
  `SootContracts.BundleRow`.
  """

  use ExUnit.Case, async: false

  alias SootContracts.{Actors, Bundle, BundleRow, Publisher}
  alias SootContracts.Test.Fixtures.Device
  alias SootContracts.Test.Helpers

  setup do
    Helpers.reset_ets!()
    ca = Helpers.fresh_ca!()

    bundle =
      Bundle.assemble(
        mqtt_resources: [Device],
        trust_chain: [ca],
        generated_at: ~U[2026-04-26 12:00:00Z]
      )
      |> Bundle.sign(ca)

    row = Publisher.publish!(bundle, ca)
    {:ok, row: row}
  end

  test ":publisher can read", %{row: row} do
    assert {:ok, ^row} = Ash.get(BundleRow, row.id, actor: Actors.system(:publisher))
  end

  test ":public_reader can read", %{row: row} do
    assert {:ok, ^row} = Ash.get(BundleRow, row.id, actor: Actors.system(:public_reader))
  end

  test "no actor is forbidden", %{row: row} do
    assert {:error, %Ash.Error.Forbidden{}} = Ash.get(BundleRow, row.id)
  end

  test "non-System actor is forbidden", %{row: row} do
    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.get(BundleRow, row.id, actor: %{type: :user})
  end

  test "System actor with an unknown :part is forbidden", %{row: row} do
    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.get(BundleRow, row.id, actor: %SootContracts.Actors.System{part: :stranger})
  end
end
