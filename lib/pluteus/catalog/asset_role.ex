defmodule Pluteus.Catalog.AssetRole do
  @moduledoc """
  One role an asset plays.

  An asset may play several. A file acquired already in the standard format is
  the acquired original and the normalized master at once, and spec-01 §5.5
  forbids storing the bytes twice to give each role a row of its own.

  The class is normative and decides what happens elsewhere — §13.7 spends
  backup capacity on the acquired and normalized classes and refuses it to the
  derived one. The role within a class is seed data, so a household may name a
  role the release never shipped without any rule that reads the class changing.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Asset

  @role_classes ~w(acquired normalized redundant derived)a

  @primary_key false
  @foreign_key_type UUIDv7
  schema "asset_roles" do
    belongs_to :asset, Asset, define_field: false

    field :asset_id, UUIDv7, primary_key: true
    field :role, :string, primary_key: true
    field :role_class, Ecto.Enum, values: @role_classes

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @spec role_classes() :: [atom()]
  def role_classes, do: @role_classes

  @doc """
  Whether a role in this class is worth backup capacity (§13.7).

  Derived assets are regenerable from a master and a recipe, so their loss costs
  the time to rebuild them and nothing else.
  """
  @spec backed_up?(atom()) :: boolean()
  def backed_up?(:derived), do: false
  def backed_up?(role_class) when role_class in @role_classes, do: true

  def changeset(asset_role, attrs) do
    asset_role
    |> cast(attrs, [:asset_id, :role, :role_class])
    |> validate_required([:asset_id, :role, :role_class])
    |> check_constraint(:role_class, name: :role_class_must_be_known)
    |> unique_constraint([:asset_id, :role], name: :asset_roles_pkey)
    |> foreign_key_constraint(:asset_id)
  end
end
