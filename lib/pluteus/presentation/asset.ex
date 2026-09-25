defmodule Pluteus.Presentation.Asset do
  @moduledoc """
  A derived artefact a surface asks for by profile name ([spec-10] §11.1).

  It is a derived asset in spec-01 §5.5's sense: regenerable from the bytes it was
  made from, never backed up (spec-01 §13.7), never a digital item. It is not an
  `asset` row, for the reasons the migration records.

  **A row exists only where the bytes exist.** There is no state column, because
  every state a client can act on is already legible without one: *generating* is
  the presence of the unique job that generates it, and *absent* is the absence of
  a row. A column would be a third account of the same fact, and two of the three
  could disagree.

  The profile is checked against §20's registry rather than a database vocabulary,
  because the registry is seed data a release replaces (spec-01 §17). A profile the
  registry does not name is refused here rather than stored and served later under a
  name nothing can resolve.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Asset, as: SourceAsset
  alias Pluteus.Catalog.Res
  alias Pluteus.Presentation.Registry

  @primary_key false
  @foreign_key_type UUIDv7
  schema "presentation_assets" do
    belongs_to :subject, Res, define_field: false
    belongs_to :source_asset, SourceAsset, define_field: false

    field :subject_id, UUIDv7, primary_key: true
    field :profile, :string, primary_key: true
    field :ordinal, :integer, primary_key: true, default: 0

    field :location, :string
    field :media_type, :string
    field :size, :integer
    field :digest, :string
    field :digest_algorithm, :string

    field :width, :integer
    field :height, :integer
    field :descriptor, :map, default: %{}

    field :source_asset_id, UUIDv7
    field :source_digest, :string

    field :generated_at, :utc_datetime_usec
    field :last_served_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @required ~w(
    subject_id profile location media_type size digest digest_algorithm
    source_asset_id source_digest generated_at last_served_at
  )a

  @optional ~w(ordinal width height descriptor)a

  @doc """
  The fields §11.1 requires of every artefact.
  """
  @spec required() :: [atom()]
  def required, do: @required

  def changeset(asset, attrs) do
    asset
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_profile()
    |> validate_number(:size, greater_than_or_equal_to: 0)
    |> validate_number(:ordinal, greater_than_or_equal_to: 0)
    |> validate_geometry()
    |> check_constraint(:size, name: :size_is_not_negative)
    |> check_constraint(:ordinal, name: :ordinal_is_not_negative)
    |> check_constraint(:width, name: :geometry_is_whole)
    |> check_constraint(:width, name: :dimensions_are_positive)
    |> unique_constraint(:location)
    |> foreign_key_constraint(:subject_id)
    |> foreign_key_constraint(:source_asset_id)
  end

  defp validate_profile(changeset) do
    validate_change(changeset, :profile, fn :profile, profile ->
      if profile in Registry.profile_names(),
        do: [],
        else: [profile: "#{profile} is not a profile §20's registry names"]
    end)
  end

  # An image states both dimensions or neither, which the database also holds. It is
  # checked here so the message names the pair rather than a constraint.
  defp validate_geometry(changeset) do
    case {get_field(changeset, :width), get_field(changeset, :height)} do
      {nil, nil} -> changeset
      {width, height} when is_integer(width) and is_integer(height) -> changeset
      _half -> add_error(changeset, :width, "a geometry states both dimensions or neither")
    end
  end
end
