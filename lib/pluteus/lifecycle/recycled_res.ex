defmodule Pluteus.Lifecycle.RecycledRes do
  @moduledoc """
  A res held in the recycle bin by one recycling.

  Keyed on the res, so no res is ever in the bin twice.
  """

  use Ecto.Schema

  alias Pluteus.Lifecycle.Recycling

  @primary_key {:res_id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "recycled_res" do
    belongs_to :recycling, Recycling

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
end
