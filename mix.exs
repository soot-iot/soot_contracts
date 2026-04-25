defmodule SootContracts.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :soot_contracts,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key],
      mod: {SootContracts.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "Contract bundle generator: signed manifest + JSON assets served at /.well-known/soot/contract."
  end

  defp package do
    [licenses: ["MIT"], links: %{}]
  end

  defp deps do
    [
      {:ash, "~> 3.24"},
      {:ash_pki, path: "../ash_pki"},
      {:soot_core, path: "../soot_core"},
      {:ash_mqtt, path: "../ash_mqtt"},
      {:soot_telemetry, path: "../soot_telemetry"},
      {:plug, "~> 1.19"},
      {:jason, "~> 1.4"}
    ]
  end
end
