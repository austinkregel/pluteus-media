defmodule Pluteus.Lifecycle.Recycling do
  @moduledoc """
  One deletion: the res a principal deleted, everything that went with it, and
  the moment it stops being restorable.

  §14.3 makes a cascade one grouped operation with one restoration, which is
  why the operation is a row and not a flag on each res it took.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Res
  alias Pluteus.Principals.Principal

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "recyclings" do
    belongs_to :root, Res, define_field: false
    belongs_to :principal, Principal, foreign_key: :recycled_by, define_field: false

    field :root_id, UUIDv7
    field :recycled_by, UUIDv7
    field :recycled_at, :utc_datetime_usec
    field :purge_after, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(recycling, attrs) do
    recycling
    |> cast(attrs, [:root_id, :recycled_by, :recycled_at, :purge_after])
    |> validate_required([:root_id, :recycled_by, :recycled_at, :purge_after])
    |> check_constraint(:purge_after, name: :purge_follows_recycling)
    |> foreign_key_constraint(:root_id)
    |> foreign_key_constraint(:recycled_by)
  end
end
