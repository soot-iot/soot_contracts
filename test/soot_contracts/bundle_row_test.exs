defmodule SootContracts.BundleRowTest do
  use ExUnit.Case, async: false

  alias SootContracts.BundleRow
  alias SootContracts.Test.Helpers

  setup do
    Helpers.reset_ets!()
    {:ok, ca: Helpers.fresh_ca!()}
  end

  defp manifest_for(fp), do: %{fingerprint: fp, version: 1}

  test "create writes a row with default :current status", %{ca: ca} do
    {:ok, row} =
      BundleRow.create("fp-1", 1, manifest_for("fp-1"), %{"a" => "b"}, ca.id, authorize?: false)

    assert row.fingerprint == "fp-1"
    assert row.status == :current
    assert row.signed_by_ca_id == ca.id
  end

  test "supersede transitions :current → :superseded", %{ca: ca} do
    {:ok, row} =
      BundleRow.create("fp-2", 1, manifest_for("fp-2"), %{}, ca.id, authorize?: false)

    {:ok, after_super} = BundleRow.supersede(row, authorize?: false)
    assert after_super.status == :superseded
  end

  test "retire transitions any status → :retired", %{ca: ca} do
    {:ok, row} =
      BundleRow.create("fp-3", 1, manifest_for("fp-3"), %{}, ca.id, authorize?: false)

    {:ok, retired_from_current} = BundleRow.retire(row, authorize?: false)
    assert retired_from_current.status == :retired

    {:ok, second} =
      BundleRow.create("fp-4", 2, manifest_for("fp-4"), %{}, ca.id, authorize?: false)

    {:ok, superseded} = BundleRow.supersede(second, authorize?: false)
    {:ok, retired_from_superseded} = BundleRow.retire(superseded, authorize?: false)
    assert retired_from_superseded.status == :retired
  end

  test "get_by_fingerprint returns the row regardless of status", %{ca: ca} do
    {:ok, row} =
      BundleRow.create("fp-5", 1, manifest_for("fp-5"), %{}, ca.id, authorize?: false)

    {:ok, _retired} = BundleRow.retire(row, authorize?: false)

    {:ok, found} = BundleRow.get_by_fingerprint("fp-5", authorize?: false)
    assert found.id == row.id
    assert found.status == :retired
  end

  test "current returns the single :current row", %{ca: ca} do
    {:ok, v1} =
      BundleRow.create("fp-a", 1, manifest_for("fp-a"), %{}, ca.id, authorize?: false)

    {:ok, _superseded} = BundleRow.supersede(v1, authorize?: false)

    {:ok, v2} =
      BundleRow.create("fp-b", 2, manifest_for("fp-b"), %{}, ca.id, authorize?: false)

    {:ok, current} = BundleRow.current(authorize?: false)
    assert current.id == v2.id
  end

  test "duplicate fingerprint create is rejected by the identity", %{ca: ca} do
    {:ok, _row} =
      BundleRow.create("fp-dupe", 1, manifest_for("fp-dupe"), %{}, ca.id, authorize?: false)

    assert {:error, _} =
             BundleRow.create(
               "fp-dupe",
               2,
               manifest_for("fp-dupe"),
               %{},
               ca.id,
               authorize?: false
             )
  end
end
