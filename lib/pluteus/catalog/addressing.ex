defmodule Pluteus.Catalog.Addressing do
  @moduledoc """
  Derives where in a resource an address falls, as a fraction of the whole.

  §8.4 forbids storing the fraction. A stored fraction loses precision on long
  media, and it is silently wrong from the moment the extent it was computed
  against is corrected — a duration read from a container header and later
  measured properly, a page count that omitted the front matter. Deriving it
  keeps exact in-resource addressing and cross-media comparison at once, so
  "halfway through" means the same thing for an episode, a novel and an album.
  """

  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Extent
  alias Pluteus.Repo

  defmodule NoExtentError do
    @moduledoc """
    Raised when the res an address targets has no recorded extent in the unit
    the selector counts in.
    """
    defexception [:message]
  end

  defmodule NotNormalizableError do
    @moduledoc """
    Raised for a selector that measures no position along a resource.
    """
    defexception [:message]
  end

  @doc """
  Where an address begins and ends, each as a fraction of the whole resource.

  Raises for a spatial or text-quote selector, which mark a region without
  measuring a distance into anything, and for a target whose extent in the
  selector's unit has not been recorded.
  """
  @spec normalized_position(Address.t()) :: {float(), float()}
  def normalized_position(%Address{} = address) do
    unit = normalizable_unit(address)
    magnitude = extent!(address.target_id, unit)
    {start_at, end_at} = span(address)

    {start_at / magnitude, end_at / magnitude}
  end

  @doc """
  Records how much of a res there is, in one unit.

  Correcting an extent is the same call: §8.4 expects the recorded figure to be
  revised, and every normalized position derived from it moves with it.
  """
  @spec record_extent(Ecto.UUID.t(), atom(), pos_integer()) ::
          {:ok, Extent.t()} | {:error, Ecto.Changeset.t()}
  def record_extent(res_id, unit, magnitude) do
    %Extent{}
    |> Extent.changeset(%{res_id: res_id, unit: unit, magnitude: magnitude})
    |> Repo.insert(
      on_conflict: {:replace, [:magnitude, :updated_at]},
      conflict_target: [:res_id, :unit]
    )
  end

  @spec get_extent(Ecto.UUID.t(), atom()) :: Extent.t() | nil
  def get_extent(res_id, unit), do: Repo.get_by(Extent, res_id: res_id, unit: unit)

  defp normalizable_unit(%Address{selector_type: selector_type} = address) do
    case Address.unit(address) do
      nil ->
        raise NotNormalizableError,
          message: "a #{selector_type} selector marks a region without a position along the whole"

      unit ->
        unit
    end
  end

  defp extent!(res_id, unit) do
    case get_extent(res_id, unit) do
      nil ->
        raise NoExtentError, message: "res #{res_id} has no extent recorded in #{unit}"

      %Extent{magnitude: magnitude} ->
        magnitude
    end
  end

  defp span(%Address{selector_type: type, start_ms: start_ms, end_ms: end_ms})
       when type in [:temporal, :spatiotemporal] do
    {start_ms, end_ms}
  end

  defp span(%Address{selector_type: :text_position} = address) do
    {address.start_offset, address.end_offset}
  end

  # A page occupies the interval between its own start and the next page's, so
  # page one of ten begins at zero rather than at a tenth.
  defp span(%Address{selector_type: :page, page_number: page_number}) do
    {page_number - 1, page_number}
  end
end
