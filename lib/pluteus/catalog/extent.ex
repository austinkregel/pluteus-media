defmodule Pluteus.Catalog.Extent do
  @moduledoc """
  How much of something there is, in a unit its selectors address it by.

  §8.4 requires normalized position to be derived rather than stored: a stored
  fraction loses precision on long media and is silently wrong the moment the
  extent is corrected. Deriving it means the extent has to be recorded, and it
  belongs on the res whose coordinate space it measures.

  The key is the pair, not the res, so one res may carry several. A scan is both
  a count of pages and a count of characters of transcript, and a page selector
  and a text selector against it normalize against different numbers.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Res

  @units ~w(millisecond character word page)a

  @primary_key false
  @foreign_key_type UUIDv7
  schema "extents" do
    belongs_to :res, Res, define_field: false

    field :res_id, UUIDv7, primary_key: true
    field :unit, Ecto.Enum, values: @units, primary_key: true
    field :magnitude, :integer

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc """
  Every unit an extent may be recorded in.

  Each is the unit some selector type in §8.3 counts in. A unit no selector
  addresses would measure nothing anything asks about.
  """
  @spec units() :: [atom()]
  def units, do: @units

  def changeset(extent, attrs) do
    extent
    |> cast(attrs, [:res_id, :unit, :magnitude])
    |> validate_required([:res_id, :unit, :magnitude])
    |> check_constraint(:unit, name: :unit_must_be_known)
    |> check_constraint(:magnitude, name: :magnitude_is_positive)
    |> foreign_key_constraint(:res_id)
  end
end
