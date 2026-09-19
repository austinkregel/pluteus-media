defmodule Pluteus.Events.ResumePosition do
  @moduledoc """
  How far through something a principal is.

  §11.1 keeps this apart from event history: it is current state, and it is
  overwritten rather than appended to. §11.2 stores it against the principal who
  authenticated, which is what carries it from the television to the phone and
  what keeps it from reaching anyone else.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Res
  alias Pluteus.Principals.Principal

  @primary_key false
  @foreign_key_type UUIDv7
  schema "resume_positions" do
    belongs_to :principal, Principal, define_field: false
    belongs_to :res, Res, define_field: false

    field :principal_id, UUIDv7, primary_key: true
    field :res_id, UUIDv7, primary_key: true
    field :position_ms, :integer
    field :comment, :string

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(position, attrs) do
    position
    |> cast(attrs, [:principal_id, :res_id, :position_ms, :comment])
    |> validate_required([:principal_id, :res_id, :position_ms])
    |> check_constraint(:position_ms, name: :position_is_not_negative)
    |> foreign_key_constraint(:principal_id)
    |> foreign_key_constraint(:res_id)
  end
end
