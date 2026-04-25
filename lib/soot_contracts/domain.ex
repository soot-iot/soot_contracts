defmodule SootContracts.Domain do
  @moduledoc "Ash domain for the bundle history."
  use Ash.Domain, otp_app: :soot_contracts, validate_config_inclusion?: false

  resources do
    resource SootContracts.BundleRow
  end
end
