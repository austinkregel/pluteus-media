defmodule Pluteus.Catalog.Work do
  @moduledoc """
  The intellectual or artistic content of a distinct creation.

  A work holds no title. Names reach it through `Pluteus.Catalog.Nomen`, which
  is what spec-01 §7.1 requires and what lets one work carry names in several
  languages, schemes and scripts without any of them being privileged by the
  schema.

  `representative_attributes` holds §6.5's characteristics users treat as inherent to the
  work, keyed by the attribute names its type names. They measure distance from the
  canonical form and order competing expressions (§8.6); they say nothing about what the
  work is about, which is categorization (§3.3).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Attributes

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "works" do
    field :representative_attributes, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(work, attrs) do
    work
    |> cast(attrs, [:id])
    |> validate_required([:id])
    |> foreign_key_constraint(:id)
  end

  @doc """
  The §6.5 attributes this work is taken to have inherently.

  `permitted` is the attribute set its type names, which the caller reads from the registry.
  """
  @spec attributes_changeset(t(), map(), [String.t()]) :: Ecto.Changeset.t()
  def attributes_changeset(work, attrs, permitted) do
    work
    |> cast(attrs, [:representative_attributes])
    |> Attributes.only(:representative_attributes, permitted)
  end
end
