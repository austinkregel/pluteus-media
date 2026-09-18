defmodule Pluteus.Catalog.WorkCreator do
  @moduledoc """
  LRM-R5, WORK was created by AGENT, many to many.

  The creator is an agent, not a principal. The author of a scanned letter and
  the household that shot a home video are ordinary creators, and neither will
  ever authenticate (spec-06 §3.4).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Res

  @primary_key false
  @foreign_key_type UUIDv7
  schema "work_creators" do
    field :work_id, UUIDv7, primary_key: true
    field :agent_id, UUIDv7, primary_key: true
    field :agent_kind, Ecto.Enum, values: Res.kinds()

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(credit, attrs) do
    credit
    |> cast(attrs, [:work_id, :agent_id, :agent_kind])
    |> validate_required([:work_id, :agent_id, :agent_kind])
    |> check_constraint(:agent_kind, name: :creator_is_an_agent)
    |> unique_constraint([:work_id, :agent_id], name: :work_creators_pkey)
    |> foreign_key_constraint(:work_id)
    |> foreign_key_constraint(:agent_id, name: :work_creators_agent_id_fkey)
  end
end
