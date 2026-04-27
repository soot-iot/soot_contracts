defmodule SootContracts.Resource.BundleRow.Preparations do
  @moduledoc false

  defmodule GetByFingerprint do
    @moduledoc false
    use Ash.Resource.Preparation
    require Ash.Query

    @impl true
    def prepare(query, _opts, _context) do
      fingerprint = Ash.Query.get_argument(query, :fingerprint)
      Ash.Query.filter(query, fingerprint == ^fingerprint)
    end
  end

  defmodule Current do
    @moduledoc false
    use Ash.Resource.Preparation
    require Ash.Query

    @impl true
    def prepare(query, _opts, _context) do
      query
      |> Ash.Query.filter(status == :current)
      |> Ash.Query.sort(version: :desc)
    end
  end
end
