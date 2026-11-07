defmodule Pluteus.Matching.PlaceKey do
  @moduledoc """
  The place res a gazetteer's identifier names, so a place is one res however many
  photographs were taken in it (spec-05 §9.7).
  """

  use Ecto.Schema

  @primary_key {:geonameid, :integer, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "place_keys" do
    field :place_id, UUIDv7
  end

  @type t :: %__MODULE__{}
end
