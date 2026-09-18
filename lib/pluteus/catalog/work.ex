defmodule Pluteus.Catalog.Work do
  @moduledoc """
  The intellectual or artistic content of a distinct creation.

  A work holds no title. Names reach it through `Pluteus.Catalog.Nomen`, which
  is what spec-01 §7.1 requires and what lets one work carry names in several
  languages, schemes and scripts without any of them being privileged by the
  schema.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "works" do
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(work, attrs) do
    work
    |> cast(attrs, [:id])
    |> validate_required([:id])
    |> foreign_key_constraint(:id)
  end
end
