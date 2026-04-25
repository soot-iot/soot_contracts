defmodule Mix.Tasks.Soot.Contracts.Build do
  @shortdoc "Assemble + sign + publish a contract bundle"

  @moduledoc """
  Build a signed bundle from named modules and persist it as the
  current `SootContracts.BundleRow`. Optionally writes every asset
  (and the manifest) to a directory for inspection.

      mix soot.contracts.build \\
            --signing-ca <CA-name> \\
            --mqtt MyApp.Device --mqtt MyApp.Device.Shadow \\
            --stream MyApp.Telemetry.Vibration --stream MyApp.Telemetry.Power \\
            [--out priv/contracts/current] \\
            [--crl-url https://crl.example.com/root.crl]

  The signing CA must be a `SoftwareKeyStrategy` CA known to
  `AshPki.CertificateAuthority` by `name`. Other strategies sign
  contracts in a follow-up.
  """

  use Mix.Task

  @switches [
    signing_ca: :string,
    mqtt: [:string, :keep],
    stream: [:string, :keep],
    out: :string,
    crl_url: :string
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(args, strict: @switches)

    ca_name = Keyword.fetch!(opts, :signing_ca)
    {:ok, ca} = AshPki.CertificateAuthority.get_by_name(ca_name)

    mqtt = opts |> Keyword.get_values(:mqtt) |> Enum.map(&load_module/1)
    streams = opts |> Keyword.get_values(:stream) |> Enum.map(&load_module/1)

    bundle =
      SootContracts.Bundle.assemble(
        mqtt_resources: mqtt,
        telemetry_streams: streams,
        trust_chain: [ca],
        crl_url: Keyword.get(opts, :crl_url)
      )

    signed = SootContracts.Bundle.sign(bundle, ca)
    row = SootContracts.Publisher.publish!(signed, ca)

    Mix.shell().info("==> published bundle #{row.fingerprint} (v#{row.version})")

    case Keyword.get(opts, :out) do
      nil ->
        :ok

      dir ->
        write_to_disk(signed, dir)
        Mix.shell().info("    assets written to #{dir}")
    end
  end

  defp load_module(name) do
    mod = Module.concat([name])
    Code.ensure_loaded!(mod)
    mod
  end

  defp write_to_disk(bundle, dir) do
    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    File.write!(
      Path.join(dir, "manifest.json"),
      SootContracts.CanonicalJSON.encode_pretty!(bundle.manifest) <> "\n"
    )

    Enum.each(bundle.assets, fn {path, body} ->
      target = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, body)
    end)
  end
end
