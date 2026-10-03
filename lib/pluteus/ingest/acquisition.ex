defmodule Pluteus.Ingest.Acquisition do
  @moduledoc """
  A file between arriving and being placed (spec-04 §4.2).

  It belongs to the custody layer. Until placement nothing in the catalog can
  hold it: an asset must realize a digital item, which must carry a
  manifestation, which must embody an expression of a work. Its identifier is
  minted here and becomes the placed asset's, and its location derives from
  that identifier alone.

  The record outlives placement. The inbox path and the probe output are
  provenance, and what placement concluded from them stays inspectable.

  States run `recorded`, `stored`, `identified`, `placed`. A record whose file
  left the inbox by other means before it was moved is `vanished`, which is
  recorded as a finding and never proceeds.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.DigitalItem

  @states ~w(recorded stored identified placed vanished)a
  @essences ~w(lossy lossless unknown not_applicable)a
  @media_classes ~w(companion audio video image text package software)a

  @doc """
  Every essence a holding's bytes may be recorded as (spec-04 §5.2).
  """
  @spec essences() :: [atom()]
  def essences, do: @essences

  @doc """
  Every broad class a holding may be placed under (spec-04 §5.3).
  """
  @spec media_classes() :: [atom()]
  def media_classes, do: @media_classes

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "acquisitions" do
    field :inbox_path, :string
    field :inbox_directory, :string
    field :location, :string
    field :state, Ecto.Enum, values: @states
    field :inbox_released_at, :utc_datetime_usec

    field :size, :integer
    field :digest, :string
    field :digest_algorithm, :string

    field :format, :string
    field :probe, :map
    field :streams, {:array, :map}
    field :essence, Ecto.Enum, values: @essences
    field :media_class, Ecto.Enum, values: @media_classes
    field :companion_kind, :string

    belongs_to :digital_item, DigitalItem

    # What placement read from the stored bytes just before writing the holding.
    # Never persisted: the measured fields above are the record's.
    field :measurement, :any, virtual: true

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc """
  The record written before any byte moves: the minted identifier, where the
  file arrived and where its bytes will lie.
  """
  def recorded_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:id, :inbox_path, :location])
    |> validate_required([:id, :inbox_path, :location])
    |> put_change(:state, :recorded)
    |> put_change(:inbox_directory, directory(attrs[:inbox_path]))
    |> unique_constraint(:inbox_path, name: :acquisitions_one_in_progress_per_path_index)
    |> unique_constraint(:location)
  end

  def stored_changeset(acquisition, measured) do
    acquisition
    |> cast(measured, [:size, :digest, :digest_algorithm])
    |> validate_required([:size, :digest, :digest_algorithm])
    |> put_change(:state, :stored)
    |> check_constraint(:state, name: :measured_once_stored)
  end

  def identified_changeset(acquisition, identified) do
    acquisition
    |> cast(identified, [:format, :probe, :streams, :essence, :media_class, :companion_kind])
    |> validate_required([:format, :essence, :media_class])
    |> put_change(:state, :identified)
    |> check_constraint(:state, name: :identified_before_placed)
    |> check_constraint(:media_class, name: :a_companion_names_its_kind)
  end

  def placed_changeset(acquisition, digital_item_id) do
    acquisition
    |> change(state: :placed, digital_item_id: digital_item_id)
    |> check_constraint(:state, name: :placed_under_a_digital_item)
  end

  @doc """
  The inbox directory of a path, which is the only evidence tying an untagged
  companion to what it describes (spec-04 §4.6). A file at the inbox root has
  the root, `"."`, as its directory.
  """
  @spec directory(String.t() | nil) :: String.t() | nil
  def directory(nil), do: nil
  def directory(inbox_path), do: Path.dirname(inbox_path)
end
