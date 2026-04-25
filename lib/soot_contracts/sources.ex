defmodule SootContracts.Sources do
  @moduledoc """
  Walks the resources / modules registered with the rest of the Soot
  framework and turns them into the raw inputs for a contract bundle.

  Inputs:
    * `:mqtt_resources` — modules using `AshMqtt.Resource` and/or
      `AshMqtt.Shadow` (devices' topic & action and shadow contracts).
    * `:telemetry_streams` — modules using `SootTelemetry.Stream`
      (devices' upload schemas + per-stream sequence/endpoint hints).
    * `:trust_chain` — list of `AshPki.CertificateAuthority` records
      whose `certificate_pem` should be pinned by devices.

  This module is intentionally pure: it inspects the modules / records
  passed in but does no DB reads on its own. The bundle assembler is
  the orchestrator.
  """

  alias AshMqtt.{BrokerConfig, Resource}
  alias AshMqtt.Resource.{Action, Topic}
  alias SootTelemetry.Schema.Fingerprint, as: SchemaFingerprint
  alias SootTelemetry.Stream.Info, as: StreamInfo

  @doc "Topics map keyed by `<resource_module>` → list of public topic descriptors."
  @spec topics([module()]) :: %{required(String.t()) => [map()]}
  def topics(resources) when is_list(resources) do
    for resource <- resources, into: %{} do
      {inspect(resource), Enum.map(BrokerConfig.topics(resource), &topic_descriptor/1)}
    end
  end

  @doc "Action map (only resources that declare actions appear)."
  @spec commands([module()]) :: %{required(String.t()) => [map()]}
  def commands(resources) when is_list(resources) do
    resources
    |> Enum.flat_map(fn resource ->
      case BrokerConfig.actions(resource) do
        [] -> []
        actions -> [{inspect(resource), Enum.map(actions, &action_descriptor/1)}]
      end
    end)
    |> Map.new()
  end

  @doc """
  Shadow descriptor map. Only resources that declared `mqtt_shadow do
  …` show up.
  """
  @spec shadows([module()]) :: %{required(String.t()) => map()}
  def shadows(resources) when is_list(resources) do
    resources
    |> Enum.filter(&BrokerConfig.uses_shadow_extension?/1)
    |> Enum.map(&{inspect(&1), shadow_descriptor(&1)})
    |> Map.new()
  end

  @doc "Per-stream descriptor map keyed by stream name."
  @spec streams([module()]) :: %{required(String.t()) => map()}
  def streams(stream_modules) when is_list(stream_modules) do
    for module <- stream_modules, into: %{} do
      name = StreamInfo.name(module)

      desc = %{
        name: name,
        tenant_scope: tenant_scope(module),
        retention: Map.new(StreamInfo.retention(module)),
        ingest_endpoint: "/ingest/#{name}",
        sequence_field: monotonic_field(module),
        schema: SchemaFingerprint.descriptor(module),
        schema_fingerprint: SchemaFingerprint.compute(module)
      }

      {Atom.to_string(name), desc}
    end
  end

  @doc """
  Trust-chain assets: PEM-encoded CA certs in chain order
  (intermediate(s) → root). The CRL distribution URL is included if
  present in `opts[:crl_url]`.
  """
  @spec trust_chain([map()], keyword()) :: %{
          required(:trust_chain_pem) => String.t(),
          required(:fingerprints) => [String.t()],
          optional(:crl_url) => String.t()
        }
  def trust_chain(cas, opts \\ []) when is_list(cas) do
    pem =
      cas
      |> Enum.map(& &1.certificate_pem)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("")

    fingerprints = Enum.map(cas, & &1.fingerprint)

    base = %{trust_chain_pem: pem, fingerprints: fingerprints}

    case Keyword.get(opts, :crl_url) do
      nil -> base
      url -> Map.put(base, :crl_url, url)
    end
  end

  # ─── descriptors ──────────────────────────────────────────────────────

  defp topic_descriptor(%Topic{} = t) do
    %{
      pattern: t.pattern,
      as: t.as,
      direction: t.direction,
      qos: t.qos,
      retain: t.retain,
      payload_format: t.payload_format,
      acl: t.acl
    }
  end

  defp action_descriptor(%Action{} = a) do
    %{
      name: a.name,
      topic: a.topic,
      reply: a.reply,
      timeout: a.timeout,
      payload_format: a.payload_format,
      qos: a.qos
    }
  end

  defp shadow_descriptor(resource) do
    info = AshMqtt.Shadow.Info

    %{
      base: info.mqtt_shadow_base!(resource),
      qos: info.mqtt_shadow_qos!(resource),
      retain: info.mqtt_shadow_retain!(resource),
      payload_format: info.mqtt_shadow_payload_format!(resource),
      desired_attributes: info.mqtt_shadow_desired_attributes!(resource),
      reported_attributes: info.mqtt_shadow_reported_attributes!(resource)
    }
  end

  defp tenant_scope(module) do
    if StreamInfo.per_tenant?(module), do: :per_tenant, else: :shared
  end

  defp monotonic_field(module) do
    case StreamInfo.monotonic_field(module) do
      nil -> nil
      field -> field.name
    end
  end

  # Hint for compile-time pruning; ensures the deps are linked even when
  # only one path is exercised at runtime.
  @compile {:no_warn_undefined, [Resource]}
end
