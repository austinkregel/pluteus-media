defmodule Pluteus.Corpus.Snapshot do
  @moduledoc """
  One snapshot of one corpus, and how far the household has got with it (spec-05 §5.6,
  §5.7).

  The date is the one the publisher states for the data, never the date it was fetched:
  §5.6 orders matches by what the data is of, and a snapshot fetched late is no newer for
  it. `files` records what was acquired, keyed by file name, with the size and digest each
  was verified at.

  A snapshot is fetched, then verified, then imported. A file that fails verification
  refuses the whole snapshot, which keeps the one before it in use.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Matching.Registry

  @states ~w(fetching verified imported refused)a

  schema "corpus_snapshots" do
    field :corpus, :string
    field :stated_on, :date
    field :state, Ecto.Enum, values: @states
    field :files, :map, default: %{}
    field :refused_because, :string
    field :imported_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc """
  A snapshot beginning to be fetched. The corpus must be one the registry holds.
  """
  def begun_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:corpus, :stated_on])
    |> validate_required([:corpus, :stated_on])
    |> validate_inclusion(:corpus, Registry.corpora())
    |> put_change(:state, :fetching)
    |> unique_constraint([:corpus, :stated_on])
  end

  @doc """
  A snapshot whose every file agreed with what its publisher stated.
  """
  def verified_changeset(snapshot, files) do
    snapshot
    |> change(state: :verified, files: files)
    |> check_constraint(:state, name: :snapshot_state_is_known)
  end

  @doc """
  A snapshot whose data is now what lookups read.
  """
  def imported_changeset(snapshot, now) do
    snapshot
    |> change(state: :imported, imported_at: now)
    |> check_constraint(:state, name: :an_import_says_when)
  end

  @doc """
  A snapshot refused, and why.
  """
  def refused_changeset(snapshot, because) do
    snapshot
    |> change(state: :refused, refused_because: because)
    |> check_constraint(:state, name: :a_refusal_says_why)
  end
end
