defmodule SootContracts.Domain do
  @moduledoc "Ash domain for the bundle history."
  # validate_config_inclusion?: false — this domain ships in a library;
  # the host app may not list it under :ash_domains in its own config.
  use Ash.Domain, otp_app: :soot_contracts, validate_config_inclusion?: false

  resources do
    resource SootContracts.BundleRow
  end
end
