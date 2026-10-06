defmodule Pluteus.Browse.Query do
  @moduledoc """
  What a browse surface is currently showing: a mode, and the facets narrowing it
  (spec-10 §9.2, §9.3).

  One value is the whole of a surface's state, which is what lets §9.3's counts be
  computed against it rather than against the catalog. Every count a surface displays
  answers the question "how many holdings would I be left with", so a count taken against
  anything but the query in hand is a false statement about what selecting it will do.

  ## Disjunctive within an axis, conjunctive across them

  Two values on one axis widen — a holding is shown if it is a photograph *or* a scan —
  and two axes narrow, because a person asking for photographs from the 1950s is asking
  for both at once. §9.3's counts follow from that and are not a separate rule: the count
  beside a value is what the query would hold with that value added to its own axis.

  ## The query is the address

  §9.4 requires every narrowing be reachable and removable on its own, so the query
  round-trips through URL parameters rather than living in a socket: a narrowed surface
  can be linked to, reloaded and gone back to. Values are comma-separated within an axis,
  since every axis carries identifiers or registry tokens and none admits a comma.

  A facet is named by one of the axes §9.2 carries, and a parameter that names none is not
  a facet: a surface's own paging and format parameters reach it in the same map, so this
  reads the axes rather than refusing what it does not recognise, as
  `Pluteus.Catalog.DeepLink.read/2` already does with a selector's dimensions.

  What is refused is a value inside an axis whose vocabulary is closed. A mode or a
  category outside the registry names something no deployment could hold, and answering
  it with an unnarrowed surface would state a narrowing that did not happen.
  """

  alias Pluteus.Ingest.Registry
  alias Pluteus.Surfaces.Registry, as: Surfaces

  @enforce_keys [:mode]
  defstruct mode: nil, facets: %{}

  @type t :: %__MODULE__{mode: String.t(), facets: %{String.t() => [String.t()]}}

  @typedoc """
  Why a request named no query this release can answer.
  """
  @type refusal :: {:unknown_mode, String.t()} | {:unknown_category, String.t()}

  @doc """
  The query a mode and a request's parameters name.

  Parameters the facet axes do not name are left alone, so a surface may carry its own
  without them reaching the query.
  """
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, refusal()}
  def parse(mode, params) do
    with :ok <- known_mode(mode),
         {:ok, facets} <- facets(params) do
      {:ok, %__MODULE__{mode: mode, facets: facets}}
    end
  end

  @doc """
  The parameters a query is carried by, which is what a link to it holds.

  An axis narrowing nothing is absent rather than empty, so one query has one address.
  """
  @spec to_params(t()) :: %{String.t() => String.t()}
  def to_params(%__MODULE__{facets: facets}) do
    for {axis, [_one | _more] = values} <- facets,
        into: %{},
        do: {axis, Enum.join(Enum.sort(values), ",")}
  end

  @doc """
  The same query with one more value on an axis. Adding one it already carries changes
  nothing, so a chip rendered twice cannot narrow twice.
  """
  @spec narrow(t(), String.t(), String.t()) :: t()
  def narrow(%__MODULE__{} = query, axis, value) do
    put(query, axis, Enum.uniq([value | Map.get(query.facets, axis, [])]))
  end

  @doc """
  The same query with one value gone from an axis.

  §9.4 requires each narrowing be removable on its own, so this takes the one value
  rather than the axis: a surface narrowed to two decades and one category loses the
  decade a person dismisses and keeps the other.
  """
  @spec widen(t(), String.t(), String.t()) :: t()
  def widen(%__MODULE__{} = query, axis, value) do
    put(query, axis, List.delete(Map.get(query.facets, axis, []), value))
  end

  @doc """
  The same query with one axis carrying nothing.

  What a facet's own counts are computed over. §9.3 makes the count beside a value what
  selecting it will hold, and selecting it widens its own axis rather than replacing the
  query, so the axis's own narrowing comes off and goes back on one value at a time.
  """
  @spec without(t(), String.t()) :: t()
  def without(%__MODULE__{} = query, axis), do: put(query, axis, [])

  @doc """
  Every value a query carries, as `{axis, value}` pairs in a stable order. What the
  "Narrowed by" chips are rendered from.
  """
  @spec narrowings(t()) :: [{String.t(), String.t()}]
  def narrowings(%__MODULE__{facets: facets}) do
    for axis <- Enum.sort(Map.keys(facets)),
        value <- Enum.sort(Map.fetch!(facets, axis)),
        do: {axis, value}
  end

  @doc """
  Whether anything narrows this query.
  """
  @spec narrowed?(t()) :: boolean()
  def narrowed?(%__MODULE__{} = query), do: narrowings(query) != []

  @doc """
  The values a query carries on one axis.
  """
  @spec on(t(), String.t()) :: [String.t()]
  def on(%__MODULE__{facets: facets}, axis), do: Map.get(facets, axis, [])

  # An axis carries a set rather than a list: the order values arrived in is not part of
  # what is being asked for, so one narrowing has one representation and one address.
  defp put(%__MODULE__{} = query, axis, values) do
    case Enum.sort(values) do
      [] -> %{query | facets: Map.delete(query.facets, axis)}
      values -> %{query | facets: Map.put(query.facets, axis, values)}
    end
  end

  defp known_mode(mode) do
    if mode in Surfaces.browse_modes(), do: :ok, else: {:error, {:unknown_mode, mode}}
  end

  defp facets(params) do
    Enum.reduce_while(Surfaces.facets(), {:ok, %{}}, fn axis, {:ok, taken} ->
      case values(axis, params[axis]) do
        {:ok, []} -> {:cont, {:ok, taken}}
        {:ok, values} -> {:cont, {:ok, Map.put(taken, axis, values)}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
  end

  defp values(_axis, nil), do: {:ok, []}

  defp values(axis, stated) when is_binary(stated) do
    stated
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
    |> admissible(axis)
  end

  # A category is a closed vocabulary, so a value outside it names nothing this
  # deployment could ever hold and the request is malformed. The other axes carry
  # identifiers, which no registry bounds: one naming nothing selects nothing, which is
  # an empty surface rather than a bad request.
  defp admissible(values, "category") do
    case Enum.reject(values, &(&1 in Registry.recordable_categories())) do
      [] -> {:ok, values}
      [unknown | _rest] -> {:error, {:unknown_category, unknown}}
    end
  end

  defp admissible(values, _identifiers), do: {:ok, values}
end
