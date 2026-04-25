defmodule SootContracts.CanonicalJSON do
  @moduledoc """
  Encode a value to JSON with map keys sorted lexicographically. Used
  everywhere we hash a structure: the same logical content always
  produces the same byte-for-byte output regardless of insertion order.
  """

  @doc "JSON-encode `value` with sorted keys at every level."
  @spec encode!(term()) :: String.t()
  def encode!(value) do
    value
    |> sort_keys()
    |> Jason.encode!()
  end

  @doc "Same as `encode!/1` but with `pretty: true`."
  @spec encode_pretty!(term()) :: String.t()
  def encode_pretty!(value) do
    value
    |> sort_keys()
    |> Jason.encode!(pretty: true)
  end

  defp sort_keys(value) when is_map(value) and not is_struct(value) do
    value
    |> Enum.map(fn {k, v} -> {to_string(k), sort_keys(v)} end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Jason.OrderedObject.new()
  end

  defp sort_keys(value) when is_list(value), do: Enum.map(value, &sort_keys/1)
  defp sort_keys(%DateTime{} = v), do: DateTime.to_iso8601(v)
  defp sort_keys(%Date{} = v), do: Date.to_iso8601(v)

  defp sort_keys(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp sort_keys(value), do: value
end
