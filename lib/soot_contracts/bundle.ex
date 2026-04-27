defmodule SootContracts.Bundle do
  @moduledoc """
  Assemble, fingerprint, sign, and verify contract bundles.

  A bundle is a map:

      %{
        manifest: %{
          version: 1,
          generated_at: iso8601,
          fingerprint: "<sha256-hex>",
          signed_by: nil | "<ca-fingerprint>",
          signature: nil | "<base64>",
          assets: %{ "<path>" => %{sha256: "<hex>", size: integer} }
        },
        assets: %{ "<path>" => binary }
      }

  `assemble/1` produces an unsigned bundle. `sign/2` adds the
  `signed_by` + `signature` fields. `verify/2` checks the signature
  against the same `AshPki.CertificateAuthority`'s public key.

  The fingerprint is the SHA-256 over the canonical JSON of the
  per-asset content hashes (so it changes iff *any* asset's bytes
  change). The signature is over the manifest body excluding the
  `signature`/`signed_by` fields, again as canonical JSON.
  """

  alias SootContracts.CanonicalJSON
  alias SootContracts.Sources

  @bundle_version 1

  @doc """
  Build an unsigned bundle from input sources.

  Options:
    * `:mqtt_resources` — list of modules using `AshMqtt.Resource` /
      `AshMqtt.Shadow`. Default: `[]`.
    * `:telemetry_streams` — list of modules using
      `SootTelemetry.Stream`. Default: `[]`.
    * `:trust_chain` — list of `AshPki.CertificateAuthority` records
      to include in `pki/trust_chain.pem`. Default: `[]`.
    * `:crl_url` — distribution-point URL for the CRL. Default: `nil`.
    * `:generated_at` — `DateTime` to stamp into the manifest. Default:
      `DateTime.utc_now/0`. Override in tests for deterministic output.
  """
  @spec assemble(keyword()) :: map()
  def assemble(opts \\ []) do
    mqtt = Keyword.get(opts, :mqtt_resources, [])
    streams = Keyword.get(opts, :telemetry_streams, [])
    trust = Keyword.get(opts, :trust_chain, [])
    crl_url = Keyword.get(opts, :crl_url)
    now = Keyword.get(opts, :generated_at, DateTime.utc_now())

    asset_blobs = build_assets(mqtt, streams, trust, crl_url)
    asset_index = Map.new(asset_blobs, fn {path, body} -> {path, asset_meta(body)} end)
    fingerprint = compute_fingerprint(asset_index)

    %{
      manifest: %{
        version: @bundle_version,
        generated_at: now,
        fingerprint: fingerprint,
        signed_by: nil,
        signature: nil,
        assets: asset_index
      },
      assets: Map.new(asset_blobs)
    }
  end

  @doc """
  Sign the bundle's manifest using `ca`'s `KeyStrategy`. Returns the
  bundle with `manifest.signed_by` and `manifest.signature` populated.
  """
  @spec sign(map(), AshPki.CertificateAuthority.t()) :: map()
  def sign(bundle, %AshPki.CertificateAuthority{} = ca) do
    body = signing_body(bundle.manifest)
    signature = sign_body(ca, body)

    manifest =
      bundle.manifest
      |> Map.put(:signed_by, ca.fingerprint)
      |> Map.put(:signature, Base.encode64(signature))

    %{bundle | manifest: manifest}
  end

  @doc """
  Verify the bundle's signature against the same CA, and that every
  asset's bytes match the SHA-256 declared in the manifest. Returns
  `{:ok, bundle}` or `{:error, reason}`.
  """
  @spec verify(map(), AshPki.CertificateAuthority.t()) ::
          {:ok, map()} | {:error, term()}
  def verify(bundle, %AshPki.CertificateAuthority{} = ca) do
    with {:ok, signature} <- decode_signature(bundle.manifest.signature),
         :ok <- verify_assets(bundle),
         body <- signing_body(bundle.manifest),
         {:ok, public} <- public_key_for(ca),
         true <- :public_key.verify(body, :sha256, signature, public) do
      {:ok, bundle}
    else
      false -> {:error, :invalid_signature}
      {:error, _} = err -> err
    end
  end

  defp verify_assets(%{manifest: %{assets: index}, assets: blobs}) do
    paths = Map.keys(index)

    case Enum.find(paths, fn path ->
           expected = index[path]
           actual_bytes = Map.get(blobs, path)
           is_nil(actual_bytes) or actual_meta(actual_bytes) != expected
         end) do
      nil ->
        case Enum.any?(Map.keys(blobs), &(not Map.has_key?(index, &1))) do
          true -> {:error, :extraneous_asset}
          false -> :ok
        end

      path ->
        {:error, {:asset_mismatch, path}}
    end
  end

  defp actual_meta(body) when is_binary(body), do: asset_meta(body)

  @doc """
  SHA-256 over the canonical JSON of the per-asset content hashes.
  Pulled into a public function so callers (and tests) can re-derive
  the fingerprint from a manifest's `:assets` index.
  """
  @spec compute_fingerprint(%{required(String.t()) => map()}) :: String.t()
  def compute_fingerprint(asset_index) do
    asset_index
    |> CanonicalJSON.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc "The body signed by `sign/2` (manifest minus the signature fields)."
  @spec signing_body(map()) :: binary()
  def signing_body(manifest) do
    manifest
    |> Map.drop([:signature, :signed_by])
    |> CanonicalJSON.encode!()
  end

  # ─── assembly helpers ──────────────────────────────────────────────────

  defp build_assets(mqtt, streams, trust, crl_url) do
    mqtt_assets =
      [
        {"topics.json", encode_pretty(Sources.topics(mqtt))},
        {"commands.json", encode_pretty(Sources.commands(mqtt))},
        {"shadow.json", encode_pretty(Sources.shadows(mqtt))}
      ]

    stream_descriptors = Sources.streams(streams)

    stream_assets =
      Enum.flat_map(stream_descriptors, fn {name, desc} ->
        [
          {"streams/#{name}.json", encode_pretty(Map.drop(desc, [:schema]))},
          {"streams/#{name}.arrow_schema", encode_pretty(desc.schema)}
        ]
      end)

    trust_assets =
      case Sources.trust_chain(trust, crl_url: crl_url) do
        %{trust_chain_pem: pem, fingerprints: fps} = entry ->
          base = [
            {"pki/trust_chain.pem", pem},
            {"pki/fingerprints.json", encode_pretty(%{fingerprints: fps})}
          ]

          case Map.get(entry, :crl_url) do
            nil -> base
            url -> [{"pki/crl_url.txt", url <> "\n"} | base]
          end
      end

    mqtt_assets ++ stream_assets ++ trust_assets
  end

  defp encode_pretty(value), do: CanonicalJSON.encode_pretty!(value) <> "\n"

  defp asset_meta(body) when is_binary(body) do
    %{
      sha256: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower),
      size: byte_size(body)
    }
  end

  # ─── signing ──────────────────────────────────────────────────────────

  defp sign_body(%AshPki.CertificateAuthority{} = ca, body) do
    strategy = AshPki.key_strategy(ca.key_strategy)

    case strategy.sign(ca.key_descriptor, body, digest_alg: :sha256) do
      {:ok, signature} ->
        signature

      {:error, reason} ->
        raise ArgumentError,
              "could not sign contract bundle with #{ca.key_strategy} CA: #{inspect(reason)}"
    end
  end

  defp decode_signature(nil), do: {:error, :unsigned_bundle}

  defp decode_signature(b64) when is_binary(b64) do
    case Base.decode64(b64) do
      {:ok, _} = ok -> ok
      :error -> {:error, :invalid_signature}
    end
  end

  defp public_key_for(%AshPki.CertificateAuthority{certificate_pem: pem}) do
    case X509.Certificate.from_pem(pem) do
      {:ok, cert} -> {:ok, X509.Certificate.public_key(cert)}
      err -> err
    end
  end
end
