defmodule Pluteus.Events.Thresholds do
  @moduledoc """
  Whether a reported position is kept, and what it means when it is past the end
  ([spec-10] §13.2).

  A position below a floor is discarded: the person did not really start. Above a
  ceiling it is discarded and the res is recorded as consumed. A res below a
  minimum length carries no position at all.

  **The floor and ceiling are proportions for short media and absolute quantities
  for long ones**, because a proportion of a long work is not a small amount: five
  per cent of a nine-hundred-page novel is forty-five pages, which is a real
  resume. An absolute ceiling is expressed as the extent remaining, since "three
  minutes of credits left" is the fact rather than a fraction of the whole.

  Both regimes are measured against the extent, so an extent nobody has recorded
  raises rather than being treated as long enough. A category the registry does
  not name raises for the same reason (spec-10 §20).
  """

  alias Pluteus.Continuity.Registry

  @typedoc """
  What §13.2 does with a report: keep it, discard it as barely begun, discard it
  and record the res consumed, keep none for a res too short to resume, or keep
  none for a res nothing has measured.

  *Unmeasured* is a state the catalog admits — spec-01 §8.4's figure is recorded
  where a probe reads one and left where it does not — and both thresholds are
  measured against it, so there is nothing to weigh the position against.
  """
  @type outcome ::
          :keep | :below_floor | :consumed | :too_short | :keeps_none | :unmeasured

  @doc """
  What to do with a position in a res of this category, whose whole extent is
  `extent` in the position's own unit.
  """
  @spec weigh(String.t(), non_neg_integer(), non_neg_integer() | nil) :: outcome()
  def weigh(category, position, extent) do
    threshold = Registry.resume_threshold(category)

    case {threshold["regime"], extent} do
      {"none", _unmeasured_or_not} -> :keeps_none
      {_regime, nil} -> :unmeasured
      {"proportional", extent} -> proportional(threshold, position, extent)
      {"absolute", extent} -> absolute(threshold, position, extent)
    end
  end

  defp proportional(threshold, position, extent) do
    cond do
      extent < minimum(threshold) -> :too_short
      position < threshold["floor"] * extent -> :below_floor
      position > threshold["ceiling"] * extent -> :consumed
      true -> :keep
    end
  end

  defp absolute(threshold, position, extent) do
    cond do
      extent < minimum(threshold) -> :too_short
      position < threshold["floor_ms"] -> :below_floor
      extent - position < threshold["ceiling_remaining_ms"] -> :consumed
      true -> :keep
    end
  end

  # A minimum length is in the unit the category's positions are in, so it is
  # named for that unit. Every category that keeps a position states one.
  defp minimum(threshold),
    do: Map.fetch!(threshold, minimum_key(threshold))

  defp minimum_key(%{"unit" => "page"}), do: "minimum_length_pages"
  defp minimum_key(%{"unit" => "millisecond"}), do: "minimum_length_ms"
end
