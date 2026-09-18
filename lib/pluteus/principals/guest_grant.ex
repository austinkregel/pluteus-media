defmodule Pluteus.Principals.GuestGrant do
  @moduledoc """
  One res a guest may read (spec-06 §6.1).

  Grants are per res. Whether they also come per collection or bounded in time
  is spec-06's open question, and its mechanism belongs to spec-07.
  """

  use Ecto.Schema

  @primary_key false
  @foreign_key_type UUIDv7
  schema "guest_grants" do
    field :principal_id, UUIDv7, primary_key: true
    field :res_id, UUIDv7, primary_key: true
    field :granted_by, UUIDv7
    field :granted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
end
