defmodule Pluteus.Repo.Migrations.GroupATimeSpanByTheDateStated do
  use Ecto.Migration

  def up do
    # spec-01 §6.3 refines LRM-R35 into the time a manifestation was issued, which needs
    # a time-span res to relate to. A time-span has no subtype table: it is a res row and
    # the name it is known by, so two holdings issued in the same year must find the same
    # row or each would carry a time-span of its own and nothing would group by date.
    #
    # The key is the date as the container stated it, which is what makes the grouping the
    # evidence's rather than a bucket chosen here: `2019` and `2019-05` are different
    # dates stated to different precisions, so they are different spans.
    #
    # Recorded by ingest outside the catalog, as the release, artist, serial and narration
    # keys are. The key is unique, so two placements stating one date serialize on it and
    # join one span. The reference is to res, which survives a purge as a tombstone.
    create table(:time_span_keys, primary_key: false) do
      add :key, :text, primary_key: true
      add :time_span_id, references(:res, type: :uuid, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end
  end

  def down do
    drop table(:time_span_keys)
  end
end
