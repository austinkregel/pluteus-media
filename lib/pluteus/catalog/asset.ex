defmodule Pluteus.Catalog.Asset do
  @moduledoc """
  One stored byte sequence realizing a digital item at one location.

  The separation from the digital item is §3.2's layer boundary. A digital item
  is a catalog fact and survives the loss of every copy of it; an asset is a
  custody fact and is meaningful only while bytes exist somewhere. Collapsing
  them makes deleting a file indistinguishable from deleting a holding.

  Roles live in their own table, because §5.5 lets one byte sequence play
  several and forbids storing it twice so that each may have a row.

  `essence` records whether the bytes have already discarded information.
  spec-03 §4.2 turns on it: a lossy record is its own normalized master, and
  re-encoding it compounds generation loss to no purpose.

  `location` is not a name. It says where the bytes are filed; the name the
  bytes arrived under is a nomen (§7), and normalization changes the one while
  overwriting the other.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.AssetRole
  alias Pluteus.Catalog.DigitalItem

  @essences ~w(lossy lossless)a

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "assets" do
    belongs_to :digital_item, DigitalItem, define_field: false
    field :digital_item_id, UUIDv7

    has_many :roles, AssetRole, foreign_key: :asset_id

    field :location, :string
    field :part_sequence, :integer

    field :size, :integer
    field :digest, :string
    field :digest_algorithm, :string
    field :format, :string
    field :essence, Ecto.Enum, values: @essences

    field :verified_at, :utc_datetime_usec
    field :verification_interval_seconds, :integer

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @spec essences() :: [atom()]
  def essences, do: @essences

  @doc """
  Whether normalizing this asset may write a second one.

  spec-03 §4.2: a lossless acquisition is re-encoded into the standard codec for
  its media class, which produces a second asset. A lossy acquisition is already
  the normalized master whatever its format, so normalization adopts it in place
  and writes nothing.
  """
  @spec normalization_plan(t()) :: :adopt | :re_encode
  def normalization_plan(%__MODULE__{essence: :lossy}), do: :adopt
  def normalization_plan(%__MODULE__{essence: :lossless}), do: :re_encode

  def changeset(asset, attrs) do
    asset
    |> cast(attrs, [
      :id,
      :digital_item_id,
      :location,
      :part_sequence,
      :size,
      :digest,
      :digest_algorithm,
      :format,
      :essence,
      :verified_at,
      :verification_interval_seconds
    ])
    |> validate_required([
      :id,
      :digital_item_id,
      :location,
      :size,
      :digest,
      :digest_algorithm,
      :format,
      :essence,
      :verification_interval_seconds
    ])
    |> check_constraint(:essence, name: :essence_must_be_known)
    |> check_constraint(:size, name: :size_is_not_negative)
    |> check_constraint(:verification_interval_seconds,
      name: :verification_interval_is_positive
    )
    |> foreign_key_constraint(:id)
    |> foreign_key_constraint(:digital_item_id)
  end
end
