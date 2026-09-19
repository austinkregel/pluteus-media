defmodule Pluteus.Repo.Migrations.CreateConsumption do
  use Ecto.Migration

  # spec-07 §6.5, §6.6. Each principal's own consumption data, none of it
  # catalog content: nothing here is recorded as a catalog write, and every row
  # is keyed by the principal it belongs to (spec-06 §6.3).
  #
  # A res these rows name may later be recycled or purged. The reference stays,
  # as an event's does (spec-01 §14.3), so a restore brings it back where it was.

  @notified ~w(stars ratings playlists play_queues now_playing)

  def change do
    create table(:stars, primary_key: false) do
      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing),
        primary_key: true

      add :res_id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true
      add :starred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:ratings, primary_key: false) do
      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing),
        primary_key: true

      add :res_id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true
      add :rating, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:ratings, :rating_is_one_to_five, check: "rating BETWEEN 1 AND 5")

    create table(:playlists, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing), null: false

      add :name, :text, null: false
      add :comment, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:playlists, [:principal_id])

    # Ordered, and a song may appear more than once, so the key is the position.
    create table(:playlist_entries, primary_key: false) do
      add :playlist_id, references(:playlists, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :position, :integer, primary_key: true
      add :res_id, references(:res, type: :uuid, on_delete: :nothing), null: false
    end

    create constraint(:playlist_entries, :playlist_position_is_not_negative,
             check: "position >= 0"
           )

    # One queue per principal. The current entry is held by index, which is
    # exact where a song appears twice; indexBasedQueue exposes it as such.
    create table(:play_queues, primary_key: false) do
      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing),
        primary_key: true

      add :current_index, :integer
      add :position_ms, :bigint, null: false
      add :changed_by, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:play_queues, :queue_position_is_not_negative, check: "position_ms >= 0")

    create table(:play_queue_entries, primary_key: false) do
      add :principal_id,
          references(:play_queues,
            column: :principal_id,
            type: :uuid,
            on_delete: :delete_all
          ),
          primary_key: true

      add :position, :integer, primary_key: true
      add :res_id, references(:res, type: :uuid, on_delete: :nothing), null: false
    end

    create constraint(:play_queue_entries, :queue_entry_position_is_not_negative,
             check: "position >= 0"
           )

    # What a principal is playing now, per client, as scrobble without
    # submission reports it. It is state, not history, and is not an event.
    create table(:now_playing, primary_key: false) do
      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing),
        primary_key: true

      add :client, :text, primary_key: true
      add :res_id, references(:res, type: :uuid, on_delete: :nothing), null: false
      add :started_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # A Subsonic bookmark is the principal's resume position, with its comment.
    alter table(:resume_positions) do
      add :comment, :text
    end

    for table <- @notified do
      execute(
        """
        CREATE TRIGGER notify_consumption
          AFTER INSERT OR UPDATE OR DELETE ON #{table}
          FOR EACH ROW EXECUTE FUNCTION notify_consumption();
        """,
        "DROP TRIGGER notify_consumption ON #{table}"
      )
    end
  end
end
