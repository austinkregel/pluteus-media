defmodule Pluteus.Principals.Device do
  @moduledoc """
  A client bound to the principal who authenticated it (spec-06 §4).

  A device is not an identity and accumulates nothing of its own: whatever is
  played on it is the binding principal's. A television everyone uses is
  bound to whoever authenticated it last, and switching viewer is switching
  principal.

  **`label` is a display string and never an identifier.** Identity is the
  device's own `id`, which is what a resume position, an event and a play queue
  are keyed by ([spec-01] §11.4). Two devices of one principal may carry the same
  label; the only cost is that a surface naming the player shows them alike, which
  is a legibility question for whoever names them rather than anything the model
  rests on.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "devices" do
    field :principal_id, UUIDv7
    field :label, :string
    field :bound_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :revoked_by, UUIDv7
    field :key_digest, :string
    field :player_number, :integer, read_after_writes: true

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(device, attrs) do
    device
    |> cast(attrs, [:principal_id, :label, :bound_at, :revoked_at, :revoked_by, :key_digest])
    |> validate_required([:principal_id, :label, :bound_at])
    |> check_constraint(:revoked_at, name: :revocation_is_attributed)
    |> unique_constraint(:key_digest)
    |> foreign_key_constraint(:principal_id)
  end
end
