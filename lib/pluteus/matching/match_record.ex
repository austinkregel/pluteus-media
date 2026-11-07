defmodule Pluteus.Matching.MatchRecord do
  @moduledoc """
  What matching asked, what it was answered, and what it concluded (spec-05 §3.3).

  A record is keyed with what a holding carries, resolved with a source's answer, and
  then applied, raised as a candidate, or found empty. A holding that carried nothing to
  ask is recorded empty with an empty query, so it is not read again on every pass
  (§11). One record per res, scheme and source is current; a later answer from the same
  source supersedes it, and both are kept, because the response is provenance that cannot
  be recovered (§3.3, §6.5).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @states ~w(keyed resolved applied candidate empty failed)a
  @source_kinds ~w(holding corpus provider)a
  @bases ~w(equality resemblance)a

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "match_records" do
    field :res_id, UUIDv7
    field :asset_id, UUIDv7
    field :scheme, :string
    field :source_kind, Ecto.Enum, values: @source_kinds
    field :source, :string
    field :rank, :string
    field :rank_order, {:array, :string}
    field :query, :map
    field :response, :map
    field :basis, Ecto.Enum, values: @bases
    field :score, :float
    field :snapshot_on, :date
    field :answered_at, :utc_datetime_usec
    field :conclusion, :map
    field :state, Ecto.Enum, values: @states
    field :superseded_by_id, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc """
  A record keyed with what a holding carries, or found empty where it carried nothing.

  A successor to a superseded record is given its identifier before it is written, so
  the record it supersedes can point at it first.
  """
  def keyed_changeset(record \\ %__MODULE__{}, attrs) do
    record
    |> cast(attrs, [
      :res_id,
      :asset_id,
      :scheme,
      :source_kind,
      :source,
      :rank,
      :rank_order,
      :query,
      :state
    ])
    |> validate_required([:res_id, :source_kind, :source, :rank, :rank_order, :query, :state])
    |> validate_inclusion(:state, [:keyed, :empty])
    |> checked()
  end

  @doc """
  A source's answer, recorded on the record that asked it.
  """
  def resolved_changeset(record, attrs) do
    record
    |> cast(attrs, [:response, :basis, :score, :snapshot_on, :answered_at, :state])
    |> validate_required([:response, :basis, :state])
    |> checked()
  end

  @doc """
  What was written, or raised, from the answer.
  """
  def concluded_changeset(record, attrs) do
    record
    |> cast(attrs, [:conclusion, :state])
    |> validate_required([:state])
    |> checked()
  end

  @doc """
  The record a later answer from the same source supersedes.
  """
  def superseded_changeset(record, successor_id) do
    record |> change(superseded_by_id: successor_id) |> checked()
  end

  defp checked(changeset) do
    changeset
    |> check_constraint(:state, name: :match_state_is_known)
    |> check_constraint(:state, name: :a_resolved_match_holds_its_answer)
    |> check_constraint(:snapshot_on, name: :a_corpus_answer_names_its_snapshot)
    |> check_constraint(:conclusion, name: :a_concluded_match_says_what_it_wrote)
    |> unique_constraint([:res_id, :scheme, :source], name: :one_current_match_per_source)
    |> foreign_key_constraint(:res_id)
    |> foreign_key_constraint(:asset_id)
  end
end
