defmodule Pluteus.Annotations.Derivation do
  @moduledoc """
  The identity of the code that produced a derived annotation (spec-02 §4.1).

  It names a tool, never an agent. LRM-E6 places software outside the agent
  class, as a tool used by an agent, so the extractor or model is recorded here
  and the agent who ran it is optional: for a household running its own pipeline
  it is always the same answer, but where provenance is disputed it is the
  accountable party.

  `input` is the res the tool ran over. Supersession compares runs of one tool
  over one input, so re-segmenting one recording supersedes that recording's
  earlier segmentation and nothing else.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Annotations.ToolVersion
  alias Pluteus.Catalog.Res

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "derivations" do
    belongs_to :tool_version, ToolVersion
    field :input_id, UUIDv7
    field :parameters, :map
    field :derived_at, :utc_datetime_usec
    field :agent_id, UUIDv7
    field :agent_kind, Ecto.Enum, values: Res.kinds()

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(derivation, attrs) do
    derivation
    |> cast(attrs, [:tool_version_id, :input_id, :parameters, :derived_at, :agent_id, :agent_kind])
    |> validate_required([:tool_version_id, :input_id, :parameters, :derived_at])
    |> check_constraint(:agent_id, name: :agent_link_is_whole)
    |> check_constraint(:agent_kind, name: :agent_is_an_agent)
    |> foreign_key_constraint(:tool_version_id)
    |> foreign_key_constraint(:input_id)
    |> foreign_key_constraint(:agent_id, name: :derivations_agent_id_fkey)
  end
end
