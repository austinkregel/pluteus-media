defmodule Pluteus.Catalog.Association do
  @moduledoc """
  LRM-R1, the association between any two res, carrying the refinement that says
  which association it is.

  LRM declares R1 at res level and expects implementations to refine it. §6.3
  refines it for place and time-span, and §7.5 refines it for the case where a
  household has already created something a later release then ships as a seed.
  One table carries all of them because the relation is one relation.

  The refinement vocabulary is seed data (§17), so nothing here constrains its
  values. The one refinement this module names is the one §7.5 makes normative:
  its effect on resolution is specified, not configured.

  An association says which layer it belongs to, as a nomen does: seeded, automatic or
  local. spec-05 lets matching replace an association it wrote and forbids it touching
  one a member asserted, and the layer is how the two are told apart.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Refinements
  alias Pluteus.Catalog.Res

  @primary_key false
  @foreign_key_type UUIDv7
  schema "associations" do
    belongs_to :subject, Res, define_field: false
    belongs_to :object, Res, define_field: false

    field :subject_id, UUIDv7
    field :object_id, UUIDv7
    field :refinement, :string
    field :provenance, Ecto.Enum, values: [:seeded, :automatic, :local]

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc """
  The refinement linking two res that are one thing (§7.5).

  A household row and a seed the release later ships for the same concept are
  linked rather than merged. Merging would require mutating the seeded row,
  which §7.5 forbids, or discarding the local one, which throws away the
  household's own provenance and assigner.

  Read from the registry rather than written here, because §17 makes the refinements
  seed data: a release renaming one changes the file and nothing else.
  """
  @spec same_thing() :: String.t()
  def same_thing, do: Refinements.name!("same-thing")

  def changeset(association, attrs) do
    association
    |> cast(attrs, [:subject_id, :object_id, :refinement, :provenance])
    |> validate_required([:subject_id, :object_id, :refinement, :provenance])
    |> check_constraint(:object_id, name: :res_is_not_associated_with_itself)
    |> check_constraint(:provenance, name: :association_provenance_is_known)
    |> unique_constraint([:subject_id, :object_id, :refinement],
      name: :associations_triple_index
    )
    |> foreign_key_constraint(:subject_id)
    |> foreign_key_constraint(:object_id)
  end
end
