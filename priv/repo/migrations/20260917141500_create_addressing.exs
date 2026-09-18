defmodule Pluteus.Repo.Migrations.CreateAddressing do
  use Ecto.Migration

  # §8.2 makes a reified address a res, so it takes a kind alongside the eleven
  # LRM entities and the two extensions of §5.2 and §5.5.
  @kinds ~w(
    res
    work
    expression
    manifestation
    item
    digital_item
    asset
    person
    collective_agent
    nomen
    place
    time_span
    address
  )

  @selector_types ~w(temporal spatial spatiotemporal text_position text_quote page)

  # §8.5. A selector is valid only where its coordinate space is stable. Duration
  # is an expression attribute, so a temporal selector against a work is
  # meaningless wherever two cuts of differing runtime exist. Resolution differs
  # per scan, which bounds a spatial selector at manifestation. Pagination is a
  # manifestation attribute on the same reasoning: another edition repaginates.
  @content ~w(expression manifestation item digital_item)
  @carrier ~w(manifestation item digital_item)

  @levels [
    {"temporal", @content},
    {"spatiotemporal", @content},
    {"text_position", @content},
    {"text_quote", @content},
    {"spatial", @carrier},
    {"page", @carrier}
  ]

  # Each selector type populates exactly one combination of column groups. The
  # check makes every other combination unrepresentable, which is what keeps the
  # set in §8.3 closed rather than conventional.
  @groups [
    {:temporal, ~w(start_ms end_ms), ~w(temporal spatiotemporal)},
    {:spatial, ~w(x_percent y_percent width_percent height_percent), ~w(spatial spatiotemporal)},
    {:text_position, ~w(text_unit start_offset end_offset), ~w(text_position)},
    {:text_quote, ~w(quote_exact), ~w(text_quote)},
    {:page, ~w(page_number), ~w(page)}
  ]

  @text_units ~w(character word)

  # §8.4 requires normalized position to be derived from the extent rather than
  # stored. The extent therefore has to be recorded somewhere, and it belongs on
  # the res whose coordinate space it measures. Keying on the unit lets one res
  # carry several: a scan is both 312 pages and 480000 characters of transcript.
  @extent_units ~w(millisecond character word page)

  def change do
    execute(
      "ALTER TABLE res DROP CONSTRAINT kind_must_be_known",
      "ALTER TABLE res ADD CONSTRAINT kind_must_be_known CHECK (#{in_list("kind", @kinds -- ["address"])})"
    )

    execute(
      "ALTER TABLE res ADD CONSTRAINT kind_must_be_known CHECK (#{in_list("kind", @kinds)})",
      "ALTER TABLE res DROP CONSTRAINT kind_must_be_known"
    )

    # The target of the composite foreign key below. `id` is already unique on
    # its own; the pair is what a reference to (id, kind) can be declared against.
    create unique_index(:res, [:id, :kind])

    create table(:extents, primary_key: false) do
      add :res_id, references(:res, type: :uuid, on_delete: :nothing),
        primary_key: true,
        null: false

      add :unit, :string, primary_key: true, null: false
      add :magnitude, :bigint, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:extents, :unit_must_be_known, check: in_list("unit", @extent_units))
    create constraint(:extents, :magnitude_is_positive, check: "magnitude > 0")

    create table(:addresses, primary_key: false) do
      add :id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true

      # Denormalized from res so that level validity is a check constraint rather
      # than a trigger. The composite foreign key added below is what keeps it
      # honest: it cannot disagree with the row it names.
      add :target_kind, :string, null: false

      add :selector_type, :string, null: false

      # §8.4 permits timestamps and percentage coordinates and forbids byte
      # offsets, frame numbers, and absolute pixel coordinates. There is no
      # column here that could hold one.
      add :start_ms, :bigint
      add :end_ms, :bigint

      add :x_percent, :float
      add :y_percent, :float
      add :width_percent, :float
      add :height_percent, :float

      add :text_unit, :string
      add :start_offset, :bigint
      add :end_offset, :bigint

      add :quote_exact, :text
      add :quote_prefix, :text
      add :quote_suffix, :text

      add :page_number, :integer

      timestamps(type: :utc_datetime_usec)
    end

    alter table(:addresses) do
      add :target_id,
          references(:res,
            type: :uuid,
            column: :id,
            with: [target_kind: :kind],
            on_delete: :nothing
          ),
          null: false
    end

    create index(:addresses, [:target_id])

    create constraint(:addresses, :selector_type_must_be_known,
             check: in_list("selector_type", @selector_types)
           )

    create constraint(:addresses, :selector_is_valid_at_target_level, check: level_check())

    for {group, columns, types} <- @groups do
      create constraint(:addresses, :"#{group}_columns_match_selector_type",
               check: group_check(columns, types)
             )
    end

    create constraint(:addresses, :text_unit_must_be_known,
             check: "text_unit IS NULL OR #{in_list("text_unit", @text_units)}"
           )

    create constraint(:addresses, :temporal_range_is_ordered,
             check: "start_ms IS NULL OR (start_ms >= 0 AND end_ms >= start_ms)"
           )

    create constraint(:addresses, :text_range_is_ordered,
             check: "start_offset IS NULL OR (start_offset >= 0 AND end_offset >= start_offset)"
           )

    # Percentages, not pixels. A region that ran off the edge of the frame would
    # address nothing, so the bound is on the far corner rather than the origin.
    create constraint(:addresses, :spatial_region_lies_within_the_frame,
             check: """
             x_percent IS NULL OR (
               x_percent >= 0 AND y_percent >= 0
               AND width_percent > 0 AND height_percent > 0
               AND x_percent + width_percent <= 100
               AND y_percent + height_percent <= 100
             )
             """
           )

    create constraint(:addresses, :page_number_is_positive,
             check: "page_number IS NULL OR page_number >= 1"
           )

    # A quote anchor without its quote addresses nothing; the surrounding
    # context is optional because a sufficiently distinctive quote needs none.
    create constraint(:addresses, :quote_context_accompanies_a_quote,
             check: "quote_exact IS NOT NULL OR (quote_prefix IS NULL AND quote_suffix IS NULL)"
           )
  end

  defp in_list(column, values) do
    "#{column} IN (#{Enum.map_join(values, ", ", &"'#{&1}'")})"
  end

  defp level_check do
    clauses =
      Enum.map_join(@levels, "\n", fn {type, kinds} ->
        "WHEN '#{type}' THEN #{in_list("target_kind", kinds)}"
      end)

    "CASE selector_type\n#{clauses}\nEND"
  end

  defp group_check(columns, types) do
    """
    num_nonnulls(#{Enum.join(columns, ", ")}) =
      CASE WHEN #{in_list("selector_type", types)} THEN #{length(columns)} ELSE 0 END
    """
  end
end
