defmodule Pluteus.Consumption.Star do
  @moduledoc """
  That a principal starred a res, and when.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  schema "stars" do
    field :principal_id, UUIDv7, primary_key: true
    field :res_id, UUIDv7, primary_key: true
    field :starred_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(star, attrs) do
    star
    |> cast(attrs, [:principal_id, :res_id, :starred_at])
    |> validate_required([:principal_id, :res_id, :starred_at])
    |> foreign_key_constraint(:res_id)
  end
end
