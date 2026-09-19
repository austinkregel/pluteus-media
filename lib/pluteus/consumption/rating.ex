defmodule Pluteus.Consumption.Rating do
  @moduledoc """
  A principal's rating of a res, one to five.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  schema "ratings" do
    field :principal_id, UUIDv7, primary_key: true
    field :res_id, UUIDv7, primary_key: true
    field :rating, :integer

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(rating, attrs) do
    rating
    |> cast(attrs, [:principal_id, :res_id, :rating])
    |> validate_required([:principal_id, :res_id, :rating])
    |> check_constraint(:rating, name: :rating_is_one_to_five)
    |> foreign_key_constraint(:res_id)
  end
end
