defmodule Pluteus.Events.ResumePosition do
  @moduledoc """
  How far through something a principal is, on one of its devices.

  §11.1 keeps this apart from event history: it is current state, and a newer
  report for a device replaces that device's row rather than appending to it.
  §11.2 stores it against the principal who authenticated, which is what carries
  it from the television to the phone and what keeps it from reaching anyone else.

  **A position is kept per device, not per res** (§11.4). Two devices holding
  different positions for one principal and one res is the ordinary case rather
  than the error case, and collapsing them to one row discards which of them a
  person was actually in front of. The device is part of the position's identity,
  because [spec-10] §13.3 keeps both and names the device of the one it shows.

  The unit is stored because the medium decides it: a time for a recording, a page
  for a scan, a position in the index for reflowable text. A proportion is never
  stored in its place, for §8.4's reason — it loses precision on long media and is
  invalidated whenever the extent is corrected.

  `sequence` and `playing` are the reporting session's, which is why §13.3 can
  order two reports that share a second and tell a statement about the present
  from one about the past.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Extent
  alias Pluteus.Catalog.Res
  alias Pluteus.Principals.Device
  alias Pluteus.Principals.Principal

  @primary_key false
  @foreign_key_type UUIDv7
  schema "resume_positions" do
    belongs_to :principal, Principal, define_field: false
    belongs_to :res, Res, define_field: false
    belongs_to :device, Device, define_field: false

    field :principal_id, UUIDv7, primary_key: true
    field :res_id, UUIDv7, primary_key: true
    field :device_id, UUIDv7, primary_key: true

    field :position, :integer
    field :unit, Ecto.Enum, values: Extent.units()
    field :reported_at, :utc_datetime_usec
    field :sequence, :integer
    field :playing, :boolean
    field :comment, :string

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @required ~w(principal_id res_id device_id position unit reported_at sequence playing)a

  @doc """
  The fields §11.4 requires of every position.
  """
  @spec required() :: [atom()]
  def required, do: @required

  def changeset(position, attrs) do
    position
    |> cast(attrs, @required ++ [:comment])
    |> validate_required(@required)
    |> check_constraint(:position, name: :position_is_not_negative)
    |> check_constraint(:sequence, name: :sequence_is_not_negative)
    |> check_constraint(:unit, name: :unit_must_be_known)
    |> foreign_key_constraint(:principal_id)
    |> foreign_key_constraint(:res_id)
    |> foreign_key_constraint(:device_id)
  end
end
