defmodule Pluteus.Catalog.Address do
  @moduledoc """
  A region within a resource: the res naming the coordinate space, and the
  selector naming the region within it (§8.2).

  LRM's smallest addressable unit is a whole entity, so a subtitle cue, a scene
  boundary, an OCR word position and a reader's highlight have no LRM form. This
  is the form.

  Every row here is reified: it holds a primary identifier per §4 and is itself
  a res, so it can be named and addressed like anything else. §8.2 makes
  reification REQUIRED wherever something must reference the region durably,
  which is every case that reaches storage.

  The columns are the whole of §8.4's permitted basis. Byte offsets, frame
  numbers and absolute pixel coordinates are forbidden there because none of
  them survives a re-encode, and there is no column here that could hold one.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Res

  @selector_types ~w(temporal spatial spatiotemporal text_position text_quote page)a

  @text_units ~w(character word)a

  @content ~w(expression manifestation item digital_item)a
  @carrier ~w(manifestation item digital_item)a

  @levels %{
    temporal: @content,
    spatiotemporal: @content,
    text_position: @content,
    text_quote: @content,
    spatial: @carrier,
    page: @carrier
  }

  @castable ~w(
    id target_id target_kind selector_type
    start_ms end_ms
    x_percent y_percent width_percent height_percent
    text_unit start_offset end_offset
    quote_exact quote_prefix quote_suffix
    page_number
  )a

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "addresses" do
    belongs_to :target, Res, define_field: false
    field :target_id, UUIDv7
    field :target_kind, Ecto.Enum, values: Res.kinds()

    field :selector_type, Ecto.Enum, values: @selector_types

    field :start_ms, :integer
    field :end_ms, :integer

    field :x_percent, :float
    field :y_percent, :float
    field :width_percent, :float
    field :height_percent, :float

    field :text_unit, Ecto.Enum, values: @text_units
    field :start_offset, :integer
    field :end_offset, :integer

    field :quote_exact, :string
    field :quote_prefix, :string
    field :quote_suffix, :string

    field :page_number, :integer

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc """
  The closed set of selector types (§8.3).

  §8.3 requires a new capability to arrive as a new type rather than as a
  re-encoding of an existing one, so this list grows and never widens.
  """
  @spec selector_types() :: [atom()]
  def selector_types, do: @selector_types

  @doc """
  The entity kinds a selector type may address (§8.5).

  Duration is an expression attribute, so a temporal selector against a work
  addresses nothing definite wherever two cuts of differing runtime exist.
  Resolution differs per scan and pagination differs per edition, which bounds
  spatial and page selectors at manifestation.
  """
  @spec valid_levels(atom()) :: [atom()]
  def valid_levels(selector_type), do: Map.fetch!(@levels, selector_type)

  @doc """
  The unit a selector counts in, which is the unit its extent is recorded in
  (§8.4).

  Two types have none. Spatial coordinates are percentages already, so there is
  no linear extent to take a fraction of, and a text quote anchors on its own
  content rather than on a count.

  A text position carries its unit, because §8.5 holds a word index to be more
  stable than a character offset and the choice between them is the caller's.
  """
  @spec unit(t()) :: atom() | nil
  def unit(%__MODULE__{selector_type: :temporal}), do: :millisecond
  def unit(%__MODULE__{selector_type: :spatiotemporal}), do: :millisecond
  def unit(%__MODULE__{selector_type: :page}), do: :page
  def unit(%__MODULE__{selector_type: :text_position, text_unit: text_unit}), do: text_unit
  def unit(%__MODULE__{selector_type: :spatial}), do: nil
  def unit(%__MODULE__{selector_type: :text_quote}), do: nil

  def changeset(address, attrs) do
    address
    |> cast(attrs, @castable)
    |> validate_required([:id, :target_id, :target_kind, :selector_type])
    |> validate_level()
    |> check_constraint(:selector_type, name: :selector_type_must_be_known)
    |> check_constraint(:target_kind, name: :selector_is_valid_at_target_level)
    |> check_constraint(:selector_type, name: :temporal_columns_match_selector_type)
    |> check_constraint(:selector_type, name: :spatial_columns_match_selector_type)
    |> check_constraint(:selector_type, name: :text_position_columns_match_selector_type)
    |> check_constraint(:selector_type, name: :text_quote_columns_match_selector_type)
    |> check_constraint(:selector_type, name: :page_columns_match_selector_type)
    |> check_constraint(:text_unit, name: :text_unit_must_be_known)
    |> check_constraint(:end_ms, name: :temporal_range_is_ordered)
    |> check_constraint(:end_offset, name: :text_range_is_ordered)
    |> check_constraint(:width_percent, name: :spatial_region_lies_within_the_frame)
    |> check_constraint(:page_number, name: :page_number_is_positive)
    |> check_constraint(:quote_prefix, name: :quote_context_accompanies_a_quote)
    |> foreign_key_constraint(:id)
    |> foreign_key_constraint(:target_id)
  end

  defp validate_level(changeset) do
    selector_type = get_field(changeset, :selector_type)
    target_kind = get_field(changeset, :target_kind)

    cond do
      is_nil(selector_type) or is_nil(target_kind) ->
        changeset

      target_kind in valid_levels(selector_type) ->
        changeset

      true ->
        add_error(
          changeset,
          :target_kind,
          "a #{selector_type} selector is not valid against a #{target_kind}",
          validation: :level
        )
    end
  end
end
