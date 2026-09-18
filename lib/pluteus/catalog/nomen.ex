defmodule Pluteus.Catalog.Nomen do
  @moduledoc """
  A designation and the res it refers to, held as an entity in its own right.

  Names carry attributes a string cannot: the scheme they belong to, the script
  they are written in, who assigned them, the context they are used in. An ISBN
  and a title differ only in scheme, which is why spec-01 §4.3 routes external
  identifiers through here instead of adding an identifier column somewhere.

  Nothing enforces uniqueness on `nomen_string` and `scheme` together. Two
  entities carrying the same external identifier is a condition §4.3 requires
  the catalog to tolerate, not an error.

  `provenance` records which layer a name belongs to. Seeded names are replaced
  wholesale by an upgrade; automatic ones are replaced by the next match; local
  ones are the household's own and are replaced by nothing.

  `derived_from_id` carries LRM-R17, where one name is built out of another —
  a transliteration, an abbreviation, a shortened form. The database will only
  accept a derivation between two names of the same res.

  `assigner_id` carries LRM-R14, `Agent assigned Nomen`, and so accepts only a
  person or a collective agent. It is not a principal: §10.1 keeps the two
  apart, and a person who names things in this household without ever logging
  in has to be recordable.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Res

  @provenances ~w(seeded automatic local)a

  @castable ~w(
    id
    res_id
    assigner_id
    derived_from_id
    assigner_kind
    provenance
    nomen_string
    scheme
    language
    script
    context_of_use
    reference_source
    intended_audience
    script_conversion
  )a

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "nomens" do
    field :provenance, Ecto.Enum, values: @provenances, default: :local
    field :nomen_string, :string
    field :scheme, :string
    field :language, :string
    field :script, :string
    field :context_of_use, :string
    field :reference_source, :string
    field :intended_audience, :string
    field :script_conversion, :string

    belongs_to :res, Res, define_field: false
    belongs_to :assigner, Res, define_field: false
    belongs_to :derived_from, __MODULE__, define_field: false

    field :res_id, UUIDv7
    field :assigner_id, UUIDv7
    field :assigner_kind, Ecto.Enum, values: Res.kinds()
    field :derived_from_id, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Every provenance layer, ranked with the most authoritative first.

  A person's own correction outranks a matched name, which outranks a shipped
  one. Resolution reads this order and nothing else decides it.
  """
  @spec provenance_rank() :: [atom()]
  def provenance_rank, do: [:local, :automatic, :seeded]

  @doc """
  Builds a changeset for a nomen.

  `language` and `assigner_id` are absent from the required set on purpose.
  A null language means the name genuinely belongs to no language (§7.2), and a
  null assigner means the household's shared vocabulary rather than one
  person's (§7.3). Neither may be inferred when missing.
  """
  def changeset(nomen, attrs) do
    nomen
    |> cast(attrs, @castable)
    |> validate_required([:id, :res_id, :nomen_string, :provenance])
    |> check_constraint(:provenance, name: :provenance_must_be_known)
    |> foreign_key_constraint(:id)
    |> foreign_key_constraint(:res_id)
    |> check_constraint(:assigner_id, name: :assigner_link_is_whole)
    |> check_constraint(:assigner_kind, name: :assigner_is_an_agent)
    |> foreign_key_constraint(:assigner_id)
    |> foreign_key_constraint(:derived_from_id, name: :nomens_derived_from_id_fkey)
  end
end
