defmodule Pluteus.Catalog.Credit do
  @moduledoc """
  Who a work's release credits, as it says it: LRM's statement of
  responsibility (spec-04 §6.4).

  A credit is a name in a role — an artist of a track, an album artist of a
  release — and names an agent from the moment it is placed: the artist for its
  MusicBrainz identifier, or for its name where it carries none (spec-01 §3.1).
  Which of LRM's two kinds of agent that artist is may be settled later, and
  narrowing it leaves the credit naming the same agent.

  A credit names a work or an expression, and the level is the distinction rather than a
  detail of storage: the author of a text is credited on the work and the narrator of a
  reading of it on the expression (§6.9), because what the narrator made is that rendering
  and not the text.

  Credits carry provenance: placement's are automatic, and a member's
  correction is local and outranks them.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @roles ~w(artist album_artist author narrator)a
  @provenances ~w(seeded automatic local)a
  @agent_kinds ~w(person collective_agent artist)a

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "credits" do
    field :work_id, UUIDv7
    field :expression_id, UUIDv7
    field :role, Ecto.Enum, values: @roles
    field :position, :integer
    field :name, :string
    field :musicbrainz_id, Ecto.UUID
    field :agent_id, UUIDv7
    field :agent_kind, Ecto.Enum, values: @agent_kinds
    field :provenance, Ecto.Enum, values: @provenances

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(credit, attrs) do
    credit
    |> cast(attrs, [
      :work_id,
      :expression_id,
      :role,
      :position,
      :name,
      :musicbrainz_id,
      :agent_id,
      :agent_kind,
      :provenance
    ])
    |> validate_required([:role, :position, :name, :provenance])
    |> check_constraint(:role, name: :credit_role_must_be_known)
    |> check_constraint(:position, name: :credit_position_is_positive)
    |> check_constraint(:provenance, name: :credit_provenance_must_be_known)
    |> check_constraint(:agent_kind, name: :credited_agent_is_an_agent)
    |> check_constraint(:agent_id, name: :credited_agent_link_is_whole)
    |> check_constraint(:work_id, name: :a_credit_names_a_work_or_an_expression)
    |> foreign_key_constraint(:work_id)
    |> foreign_key_constraint(:expression_id)
    |> foreign_key_constraint(:agent_id)
  end

  @doc """
  The roles a credit may be in.
  """
  @spec roles() :: [atom()]
  def roles, do: @roles
end
