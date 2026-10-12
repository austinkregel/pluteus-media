defmodule Pluteus.Browse.Counts do
  @moduledoc """
  What each facet value would leave a surface holding.

  A count is computed against the current query, and a count not recomputed is a false
  statement about what selecting it will do. So the number beside a value is not a
  distribution over the catalog and not a distribution over the query — it is the size of
  the query a person would be looking at *after* selecting it.

  Since values are disjunctive within an axis, selecting one widens that axis and leaves
  every other axis alone. So each axis's counts are computed over the query with that
  axis's own narrowing removed, and each value's count is that selection restricted to
  the axis's values plus the one.

  Nothing is cached. A count held from a previous render is that false statement, and
  there is no interval short enough to make it true.

  ## Why every axis is one query

  A work carries exactly one effective category, so the counts over that axis partition
  the selection and a single `group_by` gives every value at once. The axes then share
  that query, because what each of them narrows is one derivation of what the mode
  selects: `Pluteus.Browse.Entries.distributions/2` states it once and the branches read
  it, so a surface naming three facets reads the catalog once rather than three times.

  What the query already holds arrives from the caller for the same reason. It is the
  figure the surface states beside its rows, so asking for it again here would be a
  second round trip for a number already in hand — and two derivations of one figure can
  disagree, which on this surface would mean the counts not summing to the total a person
  is reading.

  The arithmetic follows from that partition rather than from a guess:

      count(value) = (the query's own size, where the axis already narrows)
                   + (the value's own share, where the value is not already selected)

  With nothing selected on the axis the first term is nought and a value's count is its
  own share. With something selected, selecting another value adds its share to what is
  already held, and selecting one already held changes nothing. A test asserts each of
  those against what selecting the value actually leaves, rather than against this
  reasoning.

  ## An axis is named even where it answers nothing

  A facet with no available values is still named and shown inert, and a control for an
  affordance that does not exist carries the reason. So an axis this release takes no
  facet on is reported inert *with its reason*, which is a
  different statement from an axis the catalog has no values for. Reporting the second
  where the first is true would say the household holds nothing of a kind it may well
  hold.
  """

  alias Pluteus.Browse.Entries
  alias Pluteus.Browse.Query
  alias Pluteus.Surfaces.Registry, as: Surfaces

  @typedoc """
  A facet's answer: the values it offers with what each would leave held, or the reason
  it offers none.
  """
  @type facet :: {:available, [{String.t(), non_neg_integer()}]} | {:inert, String.t()}

  @doc """
  Every facet axis, with what each of its values would leave the surface holding.

  `held` is how many the query holds as it stands, which is what selecting a value adds
  to.
  """
  @spec for_query(Query.t(), non_neg_integer()) :: %{String.t() => facet()}
  def for_query(%Query{} = browse, held) do
    adds = Entries.distributions(Entries.narrowable_axes(), browse)

    for axis <- Surfaces.facets(), into: %{}, do: {axis, facet(axis, browse, adds, held)}
  end

  defp facet(axis, browse, adds, held) do
    if axis in Entries.narrowable_axes(),
      do: {:available, counted(axis, browse, Map.get(adds, axis, %{}), held)},
      else: {:inert, inert(axis)}
  end

  # What a value adds is its share of the selection its own axis does not narrow, less
  # whatever that selection already holds — which is what `distributions/2` counts.
  #
  # Subtracting is what makes this right for an axis a work can carry twice. A work in
  # two decades, one of them selected, is already held — counting it again under the
  # other would promise a holding the selection would not gain. Where a work carries one
  # value there is nothing to subtract and the share is plain.
  #
  # An axis narrowing nothing adds to nothing, whatever the rest of the query holds: with
  # no value of this axis selected, every work the surface holds is one some value of it
  # accounts for, so the share is the count.
  defp counted(axis, browse, adds, held) do
    selected = Query.on(browse, axis)
    already = if selected == [], do: 0, else: held

    (Map.keys(adds) ++ selected)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn value ->
      own = if value in selected, do: 0, else: Map.get(adds, value, 0)

      {value, already + own}
    end)
  end

  # Stated per axis rather than from one sentence, because the axes do not answer nothing
  # for the same reason and a person reading the surface is owed the actual one.
  #
  # The subject is the holdings. Not the facet, not the catalogue, not this deployment:
  # what a person wants to know is why there is nothing to go by, and the answer is that
  # the things themselves do not say. Both are true of everything the household holds
  # today, and both have to be read again when something starts saying either.
  defp inert("place"), do: "None of these say where they were made."
  defp inert("language"), do: "None of these say what language they are in."
end
