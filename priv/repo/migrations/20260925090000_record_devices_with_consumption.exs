defmodule Pluteus.Repo.Migrations.RecordDevicesWithConsumption do
  use Ecto.Migration

  # spec-07 §3.3. What a client did is recorded against its device, by
  # identifier; a device's label is how it is shown, and can change without
  # rewriting history. The device is always the principal's own: each reference
  # carries the principal with it, and the pair must name one device.

  def up do
    create unique_index(:devices, [:id, :principal_id])

    execute("ALTER TABLE now_playing DROP CONSTRAINT now_playing_pkey")

    alter table(:now_playing) do
      remove :client
      add :device_id, own_device(), null: false
    end

    execute("ALTER TABLE now_playing ADD PRIMARY KEY (principal_id, device_id)")

    alter table(:play_queues) do
      remove :changed_by
      add :changed_by_device_id, own_device(), null: false
    end

    alter table(:events) do
      add :device_id, own_device()
    end
  end

  def down do
    alter table(:events) do
      remove :device_id
    end

    alter table(:play_queues) do
      remove :changed_by_device_id
      add :changed_by, :text, null: false
    end

    execute("ALTER TABLE now_playing DROP CONSTRAINT now_playing_pkey")

    alter table(:now_playing) do
      remove :device_id
      add :client, :text, null: false
    end

    execute("ALTER TABLE now_playing ADD PRIMARY KEY (principal_id, client)")

    drop unique_index(:devices, [:id, :principal_id])
  end

  defp own_device do
    references(:devices,
      type: :uuid,
      with: [principal_id: :principal_id],
      on_delete: :nothing
    )
  end
end
