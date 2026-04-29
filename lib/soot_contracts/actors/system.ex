defmodule SootContracts.Actors.System do
  @moduledoc """
  Internal-subsystem actor for `soot_contracts`. See
  `SootContracts.Actors`.
  """

  @enforce_keys [:part]
  defstruct [:part, :tenant_id]

  @type part :: :publisher | :public_reader

  @type t :: %__MODULE__{
          part: part(),
          tenant_id: String.t() | nil
        }
end
