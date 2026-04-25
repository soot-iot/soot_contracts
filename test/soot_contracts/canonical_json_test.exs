defmodule SootContracts.CanonicalJSONTest do
  use ExUnit.Case, async: true

  alias SootContracts.CanonicalJSON

  test "sorts map keys" do
    assert CanonicalJSON.encode!(%{b: 1, a: 2}) == ~s({"a":2,"b":1})
  end

  test "sorts nested map keys" do
    assert CanonicalJSON.encode!(%{outer: %{b: 1, a: 2}}) == ~s({"outer":{"a":2,"b":1}})
  end

  test "is invariant to insertion order" do
    a = CanonicalJSON.encode!(%{a: 1, b: 2, c: 3})
    b = CanonicalJSON.encode!([{:c, 3}, {:b, 2}, {:a, 1}] |> Map.new())

    assert a == b
  end

  test "encodes lists in declaration order (no list sorting)" do
    assert CanonicalJSON.encode!([3, 1, 2]) == "[3,1,2]"
  end

  test "stringifies atoms (apart from nil/true/false)" do
    assert CanonicalJSON.encode!(:foo) == ~s("foo")
    assert CanonicalJSON.encode!(nil) == "null"
    assert CanonicalJSON.encode!(true) == "true"
    assert CanonicalJSON.encode!(false) == "false"
  end

  test "DateTime is rendered as ISO 8601" do
    assert CanonicalJSON.encode!(~U[2026-04-26 12:00:00Z]) == ~s("2026-04-26T12:00:00Z")
  end

  test "encode_pretty! produces multi-line output" do
    out = CanonicalJSON.encode_pretty!(%{a: 1, b: 2})
    assert out =~ "\n"
  end
end
