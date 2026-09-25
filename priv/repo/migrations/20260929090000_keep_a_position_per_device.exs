defmodule Pluteus.Repo.Migrations.KeepAPositionPerDevice do
  use Ecto.Migration

  # spec-01 §11.4. A position records the principal, the res, the device, the
  # position in the medium's own unit, that unit, when it was reported, the
  # reporting session's own counter, and whether that session was playing.
  #
  # It is kept per device. Two devices holding different positions for one
  # principal and one res is the ordinary case, and one row per device records
  # which of them a person was in front of.
  @units ~w(millisecond character word page)

  def up do
    # The device, unit, reporting time, sequence and playing flag are all non-null
    # and none can be supplied for a row that did not record it, so the rows go.
    #
    # The table is kept: the change feed's `notify_consumption` trigger is on it.
    execute("DELETE FROM resume_positions")

    drop constraint(:resume_positions, :position_is_not_negative)

    execute("ALTER TABLE resume_positions DROP CONSTRAINT resume_positions_pkey")

    rename table(:resume_positions), :position_ms, to: :position

    alter table(:resume_positions) do
      add :device_id, own_device(), null: false
      add :unit, :string, null: false
      add :reported_at, :utc_datetime_usec, null: false
      add :sequence, :bigint, null: false
      add :playing, :boolean, null: false
    end

    execute("ALTER TABLE resume_positions ADD PRIMARY KEY (principal_id, res_id, device_id)")

    create constraint(:resume_positions, :position_is_not_negative, check: "position >= 0")
    create constraint(:resume_positions, :sequence_is_not_negative, check: "sequence >= 0")

    create constraint(:resume_positions, :unit_must_be_known,
             check: "unit IN (#{in_list(@units)})"
           )

    # spec-10 §13.4 orders the continue surface by the requesting principal's own
    # most recent interaction.
    create index(:resume_positions, [:principal_id, :reported_at])
  end

  def down do
    drop index(:resume_positions, [:principal_id, :reported_at])

    drop constraint(:resume_positions, :unit_must_be_known)
    drop constraint(:resume_positions, :sequence_is_not_negative)
    drop constraint(:resume_positions, :position_is_not_negative)

    execute("ALTER TABLE resume_positions DROP CONSTRAINT resume_positions_pkey")

    # A key of (principal, res) admits one of the rows a key of
    # (principal, res, device) holds, and which one is not derivable, so the rows go.
    execute("DELETE FROM resume_positions")

    alter table(:resume_positions) do
      remove :playing
      remove :sequence
      remove :reported_at
      remove :unit
      remove :device_id
    end

    rename table(:resume_positions), :position, to: :position_ms

    execute("ALTER TABLE resume_positions ADD PRIMARY KEY (principal_id, res_id)")

    create constraint(:resume_positions, :position_is_not_negative, check: "position_ms >= 0")
  end

  defp own_device do
    references(:devices,
      type: :uuid,
      with: [principal_id: :principal_id],
      on_delete: :nothing
    )
  end

  defp in_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
