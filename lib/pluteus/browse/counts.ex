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

  ## Why the whole axis is one query

  A work carries exactly one effective category, so the counts over that axis partition
  the selection and a single `group_by` gives every value at once. The arithmetic follows
  from that partition rather than from a guess:

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

  import Ecto.Query

  alias Pluteus.Browse.Entries
  alias Pluteus.Browse.Query
  alias Pluteus.Repo
  alias Pluteus.Surfaces.Registry, as: Surfaces

  @typedoc """
  A facet's answer: the values it offers with what each would leave held, or the reason
  it offers none.
  """
  @type facet :: {:available, [{String.t(), non_neg_integer()}]} | {:inert, String.t()}

  @doc """
  Every facet axis, with what each of its values would leave the surface holding.
  """
  @spec for_query(Query.t()) :: %{String.t() => facet()}
  def for_query(%Query{} = browse) do
    for axis <- Surfaces.facets(), into: %{}, do: {axis, facet(axis, browse)}
  end

  defp facet(axis, browse) do
    if axis in Entries.narrowable_axes(),
      do: {:available, counted(axis, browse)},
      else: {:inert, inert(axis)}
  end

  defp counted("category", browse) do
    selected = Query.on(browse, "category")
    shares = shares(Query.without(browse, "category"))
    held = if selected == [], do: 0, else: Entries.count(browse)

    (Map.keys(shares) ++ selected)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn value ->
      own = if value in selected, do: 0, else: Map.get(shares, value, 0)

      {value, held + own}
    end)
  end

  # Each value's own share of the selection the axis does not narrow. One query for the
  # axis, which is what keeps a surface's cost independent of how many values it offers.
  defp shares(%Query{} = widened) do
    Entries.base()
    |> Entries.narrow(widened)
    |> Entries.with_category()
    |> group_by([category: c], c.value)
    |> select([work: w, category: c], {c.value, count(w.id)})
    |> Repo.all()
    |> Map.new()
  end

  # Stated per axis rather than from one sentence, because the axes do not answer nothing
  # for the same reason and a person reading the surface is owed the actual one.
  defp inert("person"), do: "no facet is taken on the people a holding credits"

  defp inert("place"),
    do:
      "answering where a holding was made needs a gazetteer to reach a named place from " <>
        "a coordinate, and this deployment holds none"

  defp inert("decade"), do: "no facet is taken on when a holding was made"

  defp inert("language"),
    do: "no facet is taken on the languages a holding's expressions are in"
end
