defmodule Pluteus.Repo.Migrations.HoldAPresentationAsset do
  use Ecto.Migration

  # [spec-10] §11.1. A derived artefact a surface asks for by profile name: a graded
  # image, a poster frame, a trickplay sheet, a waveform, extracted text.
  #
  # A table of its own, and not a row in `assets`, for four reasons that are
  # properties of `assets` rather than preferences:
  #
  #   - `res_must_have_nomen` exempts only `nomen` and `address`, so an asset res
  #     must carry a nomen. Nomens are catalog and are backed up, which would put a
  #     backed-up row behind every artefact spec-01 §13.7 forbids backing up.
  #   - `record_catalog_write` is on `assets`, so filling a cache would raise a
  #     change-feed entry and a socket push per artefact, naming no catalog change.
  #   - `Assets.unverified/0` filters on no role class, so an evicted derivative
  #     would be reported as an integrity failure — the collision spec-07 §4.6 and
  #     §11.6 forbid, where an absence must not read as an error.
  #   - `assets.digital_item_id` is scalar, while a waveform's subject and the bytes
  #     it was drawn from are two different res.
  #
  # No trigger is put on this table, which is the first two reasons discharged.
  def change do
    create table(:presentation_assets, primary_key: false) do
      # What the artefact is of. A manifestation for an image or a waveform, and
      # whatever §8.1 resolves for a work's tile.
      add :subject_id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true

      # A name from §20's closed set. Not a check constraint: the registry is seed
      # data a release replaces (spec-01 §17), and a constraint would freeze the set
      # in the schema where §20 puts it in a file.
      add :profile, :string, primary_key: true

      # Which of several artefacts one profile yields: a trickplay sheet's index, a
      # page of extracted text. One artefact is ordinal zero.
      add :ordinal, :integer, primary_key: true, default: 0

      add :location, :text, null: false
      add :media_type, :text, null: false
      add :size, :bigint, null: false
      add :digest, :text, null: false
      add :digest_algorithm, :string, null: false

      # The derivative's own geometry, which is what a surface reserves space for.
      # Absent for an artefact that is not an image.
      add :width, :integer
      add :height, :integer

      # What the artefact declares about itself: an image's width, a waveform's
      # point count and points per second, a sheet's interval and tiling. Criterion
      # 30 reads this, so a surface cannot offer a zoom the bytes do not support.
      add :descriptor, :map, null: false, default: %{}

      # The bytes it was made from, and their digest then. A source whose digest has
      # moved since makes this artefact stale, which is detectable rather than
      # assumed.
      add :source_asset_id, references(:assets, type: :uuid, on_delete: :nothing), null: false
      add :source_digest, :text, null: false

      add :generated_at, :utc_datetime_usec, null: false

      # Eviction is least-recently-served first (§11.6), so the order it runs in is
      # a column rather than a guess.
      add :last_served_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:presentation_assets, [:location])
    create index(:presentation_assets, [:subject_id])
    create index(:presentation_assets, [:source_asset_id])

    # §11.6 bounds eviction by least recently served, which is this order.
    create index(:presentation_assets, [:last_served_at])

    create constraint(:presentation_assets, :size_is_not_negative, check: "size >= 0")

    create constraint(:presentation_assets, :ordinal_is_not_negative, check: "ordinal >= 0")

    # An image states both dimensions or neither. One without the other is a box no
    # surface can reserve.
    create constraint(:presentation_assets, :geometry_is_whole,
             check: "num_nulls(width, height) IN (0, 2)"
           )

    create constraint(:presentation_assets, :dimensions_are_positive,
             check: "(width IS NULL OR width > 0) AND (height IS NULL OR height > 0)"
           )

    # §11.6's observability: a run is a row, inserted when it starts and completed
    # when it ends, so a run that crashed leaves `finished_at` null and is visible
    # rather than inferred from a disk filling up.
    create table(:presentation_evictions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      add :considered, :integer
      add :evicted, :integer
      add :bytes_reclaimed, :bigint

      timestamps(type: :utc_datetime_usec)
    end

    create index(:presentation_evictions, [:started_at])

    create constraint(:presentation_evictions, :a_finished_run_states_what_it_did,
             check: "finished_at IS NULL OR num_nulls(considered, evicted, bytes_reclaimed) = 0"
           )
  end
end
