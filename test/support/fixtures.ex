defmodule SootContracts.Test.Fixtures.Device do
  @moduledoc false

  use Ash.Resource,
    domain: SootContracts.Test.Fixtures.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshMqtt.Resource]

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read, :destroy, :create]
  end

  mqtt do
    qos(1)
    payload_format(:json)
    acl(:tenant_isolated)

    topic("tenants/:tenant_id/devices/:device_id/cmd",
      as: :cmd_in,
      direction: :inbound
    )

    topic("tenants/:tenant_id/devices/:device_id/up",
      as: :events_out,
      direction: :outbound
    )

    action :reboot, topic: "tenants/:tenant_id/devices/:device_id/cmd/reboot"
  end
end

defmodule SootContracts.Test.Fixtures.DeviceShadow do
  @moduledoc false

  use Ash.Resource,
    domain: SootContracts.Test.Fixtures.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshMqtt.Shadow]

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read, :destroy, :create]
  end

  mqtt_shadow do
    base("tenants/:tenant_id/devices/:device_id/shadow")
    as(:device_shadow)
    qos(1)
    retain(true)
    payload_format(:json)

    desired_attributes([:led, :sample_rate])
    reported_attributes([:led, :sample_rate, :uptime_s])
  end
end

defmodule SootContracts.Test.Fixtures.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource SootContracts.Test.Fixtures.Device
    resource SootContracts.Test.Fixtures.DeviceShadow
  end
end

defmodule SootContracts.Test.Fixtures.Vibration do
  @moduledoc false
  use SootTelemetry.Stream.Definition

  telemetry_stream do
    name :vibration
    tenant_scope(:per_tenant)
    retention(months: 12)

    fields do
      field :ts, :timestamp_us, required: true
      field :ingest_ts, :timestamp_us, server_set: true
      field :device_id, :string, dictionary: true
      field :tenant_id, :string, dictionary: true, server_set: true
      field :axis_x, :float32
      field :sequence, :uint64, monotonic: true
    end

    clickhouse do
      engine("MergeTree")
      order_by([:tenant_id, :device_id, :ts])
    end
  end
end

defmodule SootContracts.Test.Helpers do
  @moduledoc false

  def fresh_ca!(name \\ "test-root") do
    {:ok, ca} =
      AshPki.CertificateAuthority.create_root(
        name,
        "/CN=#{name}/O=SootContracts Test",
        %{validity_days: 365}
      )

    ca
  end

  def reset_ets! do
    for resource <- [
          AshPki.Certificate,
          AshPki.CertificateAuthority,
          AshPki.RevocationList,
          AshPki.EnrollmentToken,
          SootContracts.BundleRow
        ] do
      try do
        :ets.delete_all_objects(resource)
      rescue
        _ -> :ok
      end
    end
  end
end
