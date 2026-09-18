defmodule Pluteus.Repo.Migrations.NameStreamsByChannelCount do
  use Ecto.Migration

  # spec-01 §8.5. A stream's channel count survives a re-encode; the name a
  # codec gives its channel layout does not, since the same six channels are
  # "5.1" to one codec, "5.1(side)" to another, and unnamed once written as PCM.

  def up do
    execute "DROP INDEX addresses_one_per_stream_index"
    drop constraint(:addresses, :track_columns_match_selector_type)

    alter table(:addresses) do
      remove :stream_channel_layout
      add :stream_channels, :integer
    end

    create constraint(:addresses, :track_columns_match_selector_type,
             check: """
             num_nonnulls(stream_kind, stream_disposition, stream_ordinal) =
               CASE WHEN selector_type = 'track' THEN 3 ELSE 0 END
             AND (selector_type = 'track'
                  OR (stream_language IS NULL AND stream_channels IS NULL))
             """
           )

    create constraint(:addresses, :stream_channels_is_positive,
             check: "stream_channels IS NULL OR stream_channels >= 1"
           )

    execute """
    CREATE UNIQUE INDEX addresses_one_per_stream_index
      ON addresses (target_id, stream_kind, stream_language, stream_disposition,
                    stream_channels, stream_ordinal)
      NULLS NOT DISTINCT
      WHERE selector_type = 'track'
    """
  end

  def down do
    execute "DROP INDEX addresses_one_per_stream_index"
    drop constraint(:addresses, :stream_channels_is_positive)
    drop constraint(:addresses, :track_columns_match_selector_type)

    alter table(:addresses) do
      remove :stream_channels
      add :stream_channel_layout, :string
    end

    create constraint(:addresses, :track_columns_match_selector_type,
             check: """
             num_nonnulls(stream_kind, stream_disposition, stream_ordinal) =
               CASE WHEN selector_type = 'track' THEN 3 ELSE 0 END
             AND (selector_type = 'track'
                  OR (stream_language IS NULL AND stream_channel_layout IS NULL))
             """
           )

    execute """
    CREATE UNIQUE INDEX addresses_one_per_stream_index
      ON addresses (target_id, stream_kind, stream_language, stream_disposition,
                    stream_channel_layout, stream_ordinal)
      NULLS NOT DISTINCT
      WHERE selector_type = 'track'
    """
  end
end
