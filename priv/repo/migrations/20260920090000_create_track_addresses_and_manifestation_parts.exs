defmodule Pluteus.Repo.Migrations.CreateTrackAddressesAndManifestationParts do
  use Ecto.Migration

  @essences ~w(lossy lossless unknown not_applicable)
  @prior_essences ~w(lossy lossless)

  @selector_types ~w(temporal spatial spatiotemporal text_position text_quote page track)
  @prior_selector_types ~w(temporal spatial spatiotemporal text_position text_quote page)

  @content ~w(expression manifestation item digital_item)
  @carrier ~w(manifestation item digital_item)

  # spec-01 §8.5. A temporal or spatiotemporal selector may also target a
  # reified track address, which is how one region of one stream is addressed.
  # That the targeted address is a track is checked by trigger, since it is a
  # fact about another row.
  @levels [
    {"temporal", @content ++ ["address"]},
    {"spatiotemporal", @content ++ ["address"]},
    {"text_position", @content},
    {"text_quote", @content},
    {"spatial", @carrier},
    {"page", @carrier},
    {"track", @carrier}
  ]

  @prior_levels [
    {"temporal", @content},
    {"spatiotemporal", @content},
    {"text_position", @content},
    {"text_quote", @content},
    {"spatial", @carrier},
    {"page", @carrier}
  ]

  @stream_kinds ~w(audio video subtitle)

  @signals ~w(digest perceptual external_identifier member)
  @prior_signals ~w(digest perceptual external_identifier)

  @decisions ~w(same_holding same_expression distinct)
  @prior_decisions ~w(same_holding distinct)

  def up do
    replace_check(:assets, :essence_must_be_known, in_list("essence", @essences))

    # spec-01 §8.5 and spec-04 §6.5. A stream is named by what survives
    # normalization: its kind, language, disposition and channel layout, and its
    # ordinal among streams alike in all four. There is no column for its index
    # in the container or its codec, since normalization may change either.
    alter table(:addresses) do
      add :stream_kind, :string
      add :stream_language, :string
      add :stream_disposition, {:array, :string}
      add :stream_channel_layout, :string
      add :stream_ordinal, :integer
    end

    replace_check(
      :addresses,
      :selector_type_must_be_known,
      in_list("selector_type", @selector_types)
    )

    replace_check(:addresses, :selector_is_valid_at_target_level, level_check(@levels))

    create constraint(:addresses, :track_columns_match_selector_type,
             check: """
             num_nonnulls(stream_kind, stream_disposition, stream_ordinal) =
               CASE WHEN selector_type = 'track' THEN 3 ELSE 0 END
             AND (selector_type = 'track'
                  OR (stream_language IS NULL AND stream_channel_layout IS NULL))
             """
           )

    create constraint(:addresses, :stream_kind_must_be_known,
             check: "stream_kind IS NULL OR #{in_list("stream_kind", @stream_kinds)}"
           )

    create constraint(:addresses, :stream_ordinal_is_positive,
             check: "stream_ordinal IS NULL OR stream_ordinal >= 1"
           )

    # One address per stream of a carrier. Placement running again finds the
    # address it made rather than making another.
    execute """
    CREATE UNIQUE INDEX addresses_one_per_stream_index
      ON addresses (target_id, stream_kind, stream_language, stream_disposition,
                    stream_channel_layout, stream_ordinal)
      NULLS NOT DISTINCT
      WHERE selector_type = 'track'
    """

    execute """
    CREATE FUNCTION address_targets_a_track() RETURNS trigger AS $$
    BEGIN
      IF NEW.target_kind = 'address' AND NOT EXISTS (
        SELECT 1 FROM addresses WHERE id = NEW.target_id AND selector_type = 'track'
      ) THEN
        RAISE EXCEPTION 'address % targets address %, which is not a track',
          NEW.id, NEW.target_id
          USING ERRCODE = '23514', CONSTRAINT = 'address_targets_a_track';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER address_targets_a_track
      BEFORE INSERT OR UPDATE ON addresses
      FOR EACH ROW EXECUTE FUNCTION address_targets_a_track();
    """

    # LRM-R26, whole-part between manifestations: a release and its media, a
    # medium and its tracks. The position is the arrangement of spec-01 §12.1,
    # unique within its whole. Uniqueness is checked at commit, so a reorder is
    # one grouped update rather than a sequence that must dodge its own rows.
    create table(:manifestation_parts, primary_key: false) do
      add :whole_id, references(:manifestations, type: :uuid, on_delete: :nothing), null: false
      add :part_id, references(:manifestations, type: :uuid, on_delete: :nothing), null: false
      add :position, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:manifestation_parts, [:whole_id, :part_id])
    create index(:manifestation_parts, [:part_id])

    create constraint(:manifestation_parts, :manifestation_is_not_its_own_part,
             check: "whole_id <> part_id"
           )

    create constraint(:manifestation_parts, :position_is_positive,
             check: "position IS NULL OR position >= 1"
           )

    execute """
    ALTER TABLE manifestation_parts
      ADD CONSTRAINT one_part_per_position UNIQUE (whole_id, position)
      DEFERRABLE INITIALLY DEFERRED
    """

    execute """
    CREATE TRIGGER record_catalog_write
      AFTER INSERT OR UPDATE OR DELETE ON manifestation_parts
      FOR EACH ROW EXECUTE FUNCTION record_catalog_write('whole_id', 'part_id');
    """

    # spec-03 §8.3. A member may raise a pair no signal found, and a candidate
    # so raised records who raised it.
    alter table(:duplicate_candidates) do
      add :raised_by, references(:principals, type: :uuid, on_delete: :nothing)
    end

    replace_check(:duplicate_candidates, :signal_must_be_known, in_list("signal", @signals))

    replace_check(
      :duplicate_candidates,
      :decision_must_be_known,
      "decision IS NULL OR #{in_list("decision", @decisions)}"
    )

    create constraint(:duplicate_candidates, :a_member_candidate_names_its_member,
             check: "(signal = 'member') = (raised_by IS NOT NULL)"
           )
  end

  def down do
    drop constraint(:duplicate_candidates, :a_member_candidate_names_its_member)

    replace_check(
      :duplicate_candidates,
      :decision_must_be_known,
      "decision IS NULL OR #{in_list("decision", @prior_decisions)}"
    )

    replace_check(:duplicate_candidates, :signal_must_be_known, in_list("signal", @prior_signals))

    drop constraint(:duplicate_candidates, "duplicate_candidates_raised_by_fkey")

    alter table(:duplicate_candidates) do
      remove :raised_by
    end

    execute "DROP TRIGGER record_catalog_write ON manifestation_parts"
    drop table(:manifestation_parts)

    execute "DROP TRIGGER address_targets_a_track ON addresses"
    execute "DROP FUNCTION address_targets_a_track()"
    execute "DROP INDEX addresses_one_per_stream_index"

    drop constraint(:addresses, :stream_ordinal_is_positive)
    drop constraint(:addresses, :stream_kind_must_be_known)
    drop constraint(:addresses, :track_columns_match_selector_type)

    replace_check(:addresses, :selector_is_valid_at_target_level, level_check(@prior_levels))

    replace_check(
      :addresses,
      :selector_type_must_be_known,
      in_list("selector_type", @prior_selector_types)
    )

    alter table(:addresses) do
      remove :stream_ordinal
      remove :stream_channel_layout
      remove :stream_disposition
      remove :stream_language
      remove :stream_kind
    end

    replace_check(:assets, :essence_must_be_known, in_list("essence", @prior_essences))
  end

  defp replace_check(table, name, check) do
    drop constraint(table, name)
    create constraint(table, name, check: check)
  end

  defp in_list(column, values) do
    "#{column} IN (#{Enum.map_join(values, ", ", &"'#{&1}'")})"
  end

  defp level_check(levels) do
    clauses =
      Enum.map_join(levels, "\n", fn {type, kinds} ->
        "WHEN '#{type}' THEN #{in_list("target_kind", kinds)}"
      end)

    "CASE selector_type\n#{clauses}\nEND"
  end
end
