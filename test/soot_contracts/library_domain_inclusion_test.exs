defmodule SootContracts.LibraryDomainInclusionTest do
  @moduledoc """
  Regression: a consumer-namespaced resource declaring
  `domain: SootContracts.Domain` must compile.

  Without `allow_unregistered? true` on `SootContracts.Domain`, Ash's
  `VerifyAcceptedByDomain` verifier raises at module-load time:

      ** (RuntimeError) Resource SootContracts.LibraryDomainInclusionTest.
      ConsumerBundleRow declared that its domain is
      SootContracts.Domain, but that domain does not accept this resource.

  If the verifier fires, this file fails to compile and the whole
  test suite errors out — that is the intended failure mode.
  """
  use ExUnit.Case, async: true

  defmodule ConsumerBundleRow do
    @moduledoc false

    use Ash.Resource,
      otp_app: :soot_contracts,
      domain: SootContracts.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [SootContracts.Resource.BundleRow]

    ets do
      private? false
    end
  end

  test "consumer-namespaced module pointing at SootContracts.Domain compiles" do
    assert Code.ensure_loaded?(ConsumerBundleRow)
    assert is_list(Spark.Dsl.Extension.get_entities(ConsumerBundleRow, [:attributes]))
  end
end
