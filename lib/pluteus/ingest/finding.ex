defmodule Pluteus.Ingest.Finding do
  @moduledoc """
  Something an ingest stage could not do, or found that it must not guess
  about, recorded for a person to see (spec-04 §9).

  A finding is recorded against what the stage was working on: the acquisition
  record for acquisition, identification and placement; the digital item for
  normalization; the input, tool and version for analysis. Stray bytes under
  primary storage have no record at all, and bytes a purge could not remove
  have outlived theirs, so each is recorded against its location. A corpus that
  will not fetch or verify is recorded against the corpus (spec-05 §12).

  An uncleared finding keeps its subject out of the stage's due work. Clearing
  one is a person asking for it to be tried again, and the finding stays on
  record with who cleared it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @stages ~w(acquire examine identify place normalize analyse purge credit corpus)a

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "ingest_findings" do
    field :stage, Ecto.Enum, values: @stages
    field :kind, :string
    field :permanent, :boolean
    field :detail, :map, default: %{}

    field :acquisition_id, UUIDv7
    field :location, :string
    field :digital_item_id, UUIDv7
    field :input_id, UUIDv7
    field :tool_version_id, UUIDv7
    field :musicbrainz_id, Ecto.UUID
    field :corpus, :string

    field :recorded_at, :utc_datetime_usec
    field :cleared_at, :utc_datetime_usec
    field :cleared_by, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(finding, attrs) do
    finding
    |> cast(attrs, [
      :stage,
      :kind,
      :permanent,
      :detail,
      :acquisition_id,
      :location,
      :digital_item_id,
      :input_id,
      :tool_version_id,
      :musicbrainz_id,
      :corpus,
      :recorded_at
    ])
    |> validate_required([:stage, :kind, :permanent, :recorded_at])
    |> check_constraint(:stage, name: :a_finding_has_a_subject)
    |> check_constraint(:tool_version_id, name: :an_analysis_finding_names_its_tool)
    |> unique_constraint(:location, name: :ingest_findings_one_open_per_location_index)
    |> unique_constraint(:musicbrainz_id,
      name: :ingest_findings_one_open_per_musicbrainz_id_index
    )
    |> unique_constraint(:corpus, name: :ingest_findings_one_open_per_corpus_index)
  end

  def clear_changeset(finding, principal_id, now) do
    finding
    |> change(cleared_at: now, cleared_by: principal_id)
    |> check_constraint(:cleared_at, name: :clearing_is_attributed)
  end
end
