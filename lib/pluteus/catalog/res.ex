defmodule Pluteus.Catalog.Res do
  @moduledoc """
  The single identifier space every catalogued thing occupies.

  LRM places one top entity above all others, and this table is it. Subtype
  tables key on a row here rather than minting their own identifiers, which is
  what allows a relation whose range is "any res" — an appellation, a subject,
  an association with a place or time-span — to be a plain foreign key.

  `kind` records which subtype a row belongs to. It is not a substitute for the
  subtype's own row.
  """

  use Ecto.Schema

  import Ecto.Changeset

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
    artist
    nomen
    place
    time_span
    address
    annotation
  )a

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "res" do
    field :kind, Ecto.Enum, values: @kinds

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Every kind a res row may take.

  `agent` is absent by construction: LRM-E6 is the union of person and
  collective agent, so nothing is an agent without being one of those. An
  artist is an agent of an undetermined one of the two (spec-01 §3.1), and is
  the one kind a row may leave, by being narrowed to the kind it turns out to
  be.
  """
  @spec kinds() :: [atom()]
  def kinds, do: @kinds

  @doc """
  The kinds §6.1 exempts from LRM-R13's lower bound.

  A nomen is itself a res, so requiring every res to be named would require
  every name to be named. A reified address is identified by the region it
  selects, and a household holds one per subtitle cue. An annotation is
  identified by its target, body and provenance, and derived ones outnumber
  every other row; a name for one would restate its tool and body type.
  """
  @spec unnamed_kinds() :: [atom()]
  def unnamed_kinds, do: ~w(nomen address annotation)a

  @doc """
  Builds a changeset for a res.

  `id` is castable so that seeded rows can be inserted under the identifier the
  release assigned them (spec-01 §4.2). Left out, one is generated.
  """
  def changeset(res, attrs) do
    res
    |> cast(attrs, [:id, :kind])
    |> validate_required([:kind])
    |> check_constraint(:kind, name: :kind_must_be_known)
    |> unique_constraint(:id, name: :res_pkey)
  end
end
