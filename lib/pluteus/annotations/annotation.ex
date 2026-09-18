defmodule Pluteus.Annotations.Annotation do
  @moduledoc """
  A body attached to a target, with the provenance of whoever or whatever
  produced it (spec-02 §3.1).

  The target is an address for a region or any res for the whole of it; a
  track's loudness and a face tag in a photograph differ only in whether the
  target is bounded.

  Exactly one of `principal_id` and `derivation_id` is set. An authored
  annotation records the principal that asserted it and, optionally, the agent
  on whose behalf — a relative identifying faces through a member's login. A
  derived annotation records the one derivation that produced it, so an
  embedding names its model and carries no extractor's version.

  The body is a map. Where it holds measurements they are addressed by name
  (spec-02 §6.1): a positional vector is not a body, because an ordering kept in
  several places misaligns old rows silently where a missing name fails visibly.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Res

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "annotations" do
    field :target_id, UUIDv7
    field :body_type, :string
    field :body, :map
    field :principal_id, UUIDv7
    field :derivation_id, UUIDv7
    field :agent_id, UUIDv7
    field :agent_kind, Ecto.Enum, values: Res.kinds()

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @spec authored?(t()) :: boolean()
  def authored?(%__MODULE__{principal_id: principal_id}), do: not is_nil(principal_id)

  def changeset(annotation, attrs) do
    annotation
    |> cast(attrs, [
      :id,
      :target_id,
      :body_type,
      :body,
      :principal_id,
      :derivation_id,
      :agent_id,
      :agent_kind
    ])
    |> validate_required([:id, :target_id, :body_type, :body])
    |> validate_provenance()
    |> check_constraint(:derivation_id, name: :provenance_is_a_principal_or_a_derivation)
    |> check_constraint(:agent_id, name: :agent_acts_through_a_principal)
    |> check_constraint(:agent_id, name: :agent_link_is_whole)
    |> check_constraint(:agent_kind, name: :agent_is_an_agent)
    |> check_constraint(:target_id, name: :authored_annotation_targets_the_resource)
    |> foreign_key_constraint(:id)
    |> foreign_key_constraint(:target_id)
    |> foreign_key_constraint(:principal_id)
    |> foreign_key_constraint(:derivation_id)
    |> foreign_key_constraint(:agent_id, name: :annotations_agent_id_fkey)
  end

  defp validate_provenance(changeset) do
    case {get_field(changeset, :principal_id), get_field(changeset, :derivation_id)} do
      {nil, nil} ->
        add_error(
          changeset,
          :principal_id,
          "an annotation is authored or derived; this is neither"
        )

      {principal_id, derivation_id} when not is_nil(principal_id) and not is_nil(derivation_id) ->
        add_error(changeset, :derivation_id, "an annotation is authored or derived, not both")

      _one ->
        changeset
    end
  end
end
