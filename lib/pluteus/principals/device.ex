defmodule Pluteus.Principals.Device do
  @moduledoc """
  A client bound to the principal who authenticated it (spec-06 §4).

  A device is not an identity and accumulates nothing of its own: whatever is
  played on it is the binding principal's. A television everyone uses is
  bound to whoever authenticated it last, and switching viewer is switching
  principal.
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

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(device, attrs) do
    device
    |> cast(attrs, [:principal_id, :label, :bound_at, :revoked_at, :revoked_by])
    |> validate_required([:principal_id, :label, :bound_at])
    |> check_constraint(:revoked_at, name: :revocation_is_attributed)
    |> foreign_key_constraint(:principal_id)
  end
end
