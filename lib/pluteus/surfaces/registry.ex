defmodule Pluteus.Surfaces.Registry do
  @moduledoc """
  The surface values spec-10 §20 holds: the nomen schemes of §6.4, the browse modes of
  §9.2 with the facets of §9.3, the per-category presentation of §12.1, the seek
  granularities of §12.3, the text track classifications of §17.4 and the accessibility
  vocabularies of §17.3.

  **§12.1 carries the shape of the category table and this registry carries its values.**
  A category placement can record and this registry omits is a holding no surface knows
  how to present, so `category_presentation/1` raises on one rather than answering.

  **An affordance is here only where something can establish it** (§17.3): each one is
  read from a container's own stream dispositions, and a hazard is not establishable from
  bytes at all, so every hazard is one a person asserts.
  """

  alias Pluteus.Registry

  @source "surfaces"

  @doc """
  The scheme reserved for an ordering nomen (§6.4).

  An ordering nomen is a nomen of its own and never a transliteration of another, because
  §6.4 forbids generating a reading as spec-01 §7.2 forbids inferring a language.
  """
  @spec ordering_scheme() :: String.t()
  def ordering_scheme, do: Map.fetch!(fetch("nomen_schemes"), "ordering")

  @doc """
  Every nomen scheme the registry names.
  """
  @spec nomen_schemes() :: [String.t()]
  def nomen_schemes, do: Map.fetch!(fetch("nomen_schemes"), "known")

  @doc """
  Every browse mode of §9.2, in the order the top level offers them.
  """
  @spec browse_modes() :: [String.t()]
  def browse_modes, do: modes() |> Map.keys() |> Enum.sort()

  @doc """
  One browse mode: what it is, the facets its surface opens with, and the facets that may
  bound an index too long to be one.
  """
  @spec browse_mode(String.t()) :: map()
  def browse_mode(mode), do: Map.fetch!(modes(), mode)

  @doc """
  The axes a facet may be taken on (§9.3).
  """
  @spec facets() :: [String.t()]
  def facets, do: fetch("browse_modes") |> Map.fetch!("facets") |> Map.fetch!("known")

  @doc """
  How a category is presented: the primary surface, the selectors it honours, and the
  presentation assets it requires (§12.1).

  A category the registry does not name raises, rather than being presented as though it
  were something else.
  """
  @spec category_presentation(String.t()) :: map()
  def category_presentation(category), do: Map.fetch!(presentations(), category)

  @doc """
  Every category the registry holds a presentation for.
  """
  @spec presented_categories() :: [String.t()]
  def presented_categories, do: presentations() |> Map.keys() |> Enum.sort()

  @doc """
  Whether a holding of this category is played rather than read or looked at.

  §12.1 gives each category one primary surface, and only three of them run a medium
  against a clock: a transport with a queue, a transport with a chapter list, and a
  player. A document is read and a photograph is looked at, so neither has a position to
  be at and neither is offered a control that would claim otherwise.

  Every surface the registry names has a clause here and there is no catch-all, so a
  surface added to the table raises until someone says which of the two it is. The
  alternative is a new surface silently joining the unplayable, which is the answer that
  looks like nothing happened.
  """
  @spec plays?(String.t()) :: boolean()
  def plays?(category) do
    category |> category_presentation() |> Map.fetch!("primary_surface") |> played?()
  end

  defp played?("transport and queue"), do: true
  defp played?("transport and chapter list"), do: true
  defp played?("player"), do: true
  defp played?("viewer in a justified grid"), do: false
  defp played?("scan beside its transcript"), do: false
  defp played?("reader"), do: false
  defp played?("page reader"), do: false
  defp played?("its entity page, listing its episodes"), do: false
  defp played?("its entity page, listing its issues"), do: false
  defp played?("its entity page, and no player"), do: false
  defp played?("never its own surface"), do: false

  @doc """
  How a category is identified on a surface: the glyph that says which it is, the broad
  class whose colour groups it, and the word a household uses for it.

  Raises for a category nothing draws. A companion is the case: it is never presented as
  a holding, so it carries no glyph and no colour, and a surface reaching for one has
  mistaken what it is looking at rather than found a gap to fill in.
  """
  @spec category_icon(String.t()) :: %{
          glyph: String.t(),
          class: String.t(),
          name: String.t(),
          members: String.t() | nil
        }
  def category_icon(category) do
    %{"glyph" => glyph, "class" => class, "name" => name} =
      drawn = fetch("category_icons") |> Map.fetch!("of_category") |> Map.fetch!(category)

    %{glyph: glyph, class: class, name: name, members: drawn["members"]}
  end

  @doc """
  Every category something draws.
  """
  @spec drawn_categories() :: [String.t()]
  def drawn_categories,
    do: fetch("category_icons") |> Map.fetch!("of_category") |> Map.keys() |> Enum.sort()

  @doc """
  The small and large position steps of §12.3, in the unit the medium is measured along.
  """
  @spec seek_granularity(String.t() | atom()) :: map()
  def seek_granularity(unit),
    do: fetch("seek_granularities") |> Map.fetch!("of_unit") |> Map.fetch!(to_string(unit))

  @doc """
  The classifications a text track may carry (§17.4).
  """
  @spec text_track_classifications() :: [String.t()]
  def text_track_classifications, do: Map.fetch!(fetch("text_track_classifications"), "known")

  @doc """
  The classification a text track carries where no container flag establishes one.
  """
  @spec unknown_classification() :: String.t()
  def unknown_classification, do: Map.fetch!(fetch("text_track_classifications"), "default")

  @doc """
  The accessibility affordances a res may be recorded as carrying (§17.3).
  """
  @spec affordances() :: [String.t()]
  def affordances, do: fetch("accessibility") |> Map.fetch!("affordances") |> Map.keys()

  @doc """
  The hazards a res may be recorded as carrying (§17.3), each of them a person's assertion.
  """
  @spec hazards() :: [String.t()]
  def hazards, do: fetch("accessibility") |> Map.fetch!("hazards") |> Map.keys()

  defp modes, do: fetch("browse_modes") |> Map.fetch!("modes")

  defp presentations, do: fetch("category_presentation") |> Map.fetch!("of_category")

  defp fetch(key), do: Map.fetch!(registry(), key)

  defp registry, do: Registry.read(@source)
end
