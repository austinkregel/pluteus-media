defmodule Pluteus.Principals.Device do
  @moduledoc """
  The thing that plays: a client a principal has enrolled on (spec-06 §4).

  A device is not an identity and accumulates nothing of its own (§4, §4.1): what
  is played on it is the playing principal's, and the device is recorded with an
  event only as the screen it happened on. It holds no principal, because a
  credential holds one — see `Pluteus.Principals.DeviceCredential`, which §4.1
  permits a device to have several of, one per principal, each separately
  revocable.

  What lives here is what belongs to the device rather than to any credential on
  it. `label` is a display string and never an identifier: identity is the
  device's own `id`, which is what a resume position, an event and a play queue
  are keyed by ([spec-01] §11.4). Two devices may carry the same label; the only
  cost is that a surface naming the player shows them alike, which is a legibility
  question for whoever names them rather than anything the model rests on.

  `player_number` is the device's on the OpenSubsonic surface, which types a
  player id as an integer (spec-07 §3.3). It is the device's and not a
  credential's, because a player is a piece of hardware: one television enrolled
  for two people is one player.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Principals.DeviceCredential

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "devices" do
    field :label, :string
    field :player_number, :integer, read_after_writes: true

    has_many :credentials, DeviceCredential, foreign_key: :device_id

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(device, attrs) do
    device
    |> cast(attrs, [:label])
    |> validate_required([:label])
  end
end
