defmodule Pluteus.Browse.Query do
  @moduledoc """
  What a browse surface is currently showing: a mode, and the facets narrowing it.

  One value is the whole of a surface's state, which is what lets the counts be
  computed against it rather than against the catalog. Every count a surface displays
  answers the question "how many holdings would I be left with", so a count taken against
  anything but the query in hand is a false statement about what selecting it will do.

  ## Disjunctive within an axis, conjunctive across them

  Two values on one axis widen — a holding is shown if it is a photograph *or* a scan —
  and two axes narrow, because a person asking for photographs from the 1950s is asking
  for both at once. The counts follow from that and are not a separate rule: the count
  beside a value is what the query would hold with that value added to its own axis.

  ## The query is the address

  Every narrowing has to be reachable and removable on its own, so the query round-trips
  through URL parameters rather than living in a socket: a narrowed surface can be linked
  to, reloaded and gone back to. Values are comma-separated within an axis, since every
  axis carries identifiers or registry tokens and none admits a comma.

  A facet is named by one of the known axes, and a parameter that names none is not a
  facet: a surface's own paging and format parameters reach it in the same map, so this
  reads the axes rather than refusing what it does not recognise, as
  `Pluteus.Catalog.DeepLink.read/2` already does with a selector's dimensions.

  What is refused is a value inside an axis whose vocabulary is closed. A mode or a
  category outside the registry names something no deployment could hold, and answering
  it with an unnarrowed surface would state a narrowing that did not happen.

  **Whose query it is, is part of it.** §14.3 makes Continue the requesting principal's
  own resume list and forbids composing a surface from more than one principal's
  consumption, so the principal is carried here rather than passed beside it: what a
  mode selects and what every facet count is computed against are then the same
  statement, and a count that quietly answered for the household could not arise. It is
  not a parameter — no request names it and no address carries it.

  ## A search is one more term over the same selection

  [spec-10] §9.5 makes search a surface of its own and a query "one more term over the
  current selection", so the term sits beside the facets rather than among them: it has
  no values to count and no vocabulary to refuse against, and what it narrows is the
  mode's selection, exactly as the facets do. The profile is carried with it for the same
  reason the principal is — which names a term may match is a question about whose names
  are visible, and §7.3 keeps one person's word for a thing with that person.

  A browse address never carries a term. `to_params/1` is the facets alone, and the term
  is only read by `parse_search/1`, so §9.5's rule that browsing and searching do not
  share a results page holds of the addresses as well as of the surfaces.
  """

  alias Pluteus.Catalog.Profile
  alias Pluteus.Ingest.Registry
  alias Pluteus.Surfaces.Registry, as: Surfaces

  @enforce_keys [:mode]
  defstruct mode: nil, facets: %{}, principal_id: nil, term: nil, profile: nil

  @type t :: %__MODULE__{
          mode: String.t(),
          facets: %{String.t() => [String.t()]},
          principal_id: Ecto.UUID.t() | nil,
          term: String.t() | nil,
          profile: Profile.t() | nil
        }

  @typedoc """
  Why a request named no query this release can answer.
  """
  @type refusal ::
          {:unknown_mode, String.t()}
          | {:unknown_category, String.t()}
          | {:inert_axis, String.t()}

  # The axes a query may narrow on. Declared here rather than where the narrowing is
  # implemented, because what a query can express is what an address can ask for: a
  # request naming any other axis is refused before anything tries to answer it.
  @narrowable ~w(category decade person)

  @doc """
  The axes a query may narrow on. The rest are named and inert.
  """
  @spec narrowable_axes() :: [String.t()]
  def narrowable_axes, do: @narrowable

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
  The search a request's parameters name: the term in `q`, over the selection of the mode
  in `in`, narrowed by the facets beside them.

  The mode defaults to Everything, because a search reached from no mode — from an
  entity page, say — is a search of the whole catalogue. A request naming no term is a
  search not yet asked, which the surface answers by offering the field.
  """
  @spec parse_search(map()) :: {:ok, t()} | {:error, refusal()}
  def parse_search(params) do
    with {:ok, query} <- parse(Map.get(params, "in", "everything"), params) do
      {:ok, search(query, params["q"])}
    end
  end

  @doc """
  The same selection searched for a term. Surrounding space is not part of what anybody
  typed, and a term of nothing is no term.
  """
  @spec search(t(), String.t() | nil) :: t()
  def search(%__MODULE__{} = query, nil), do: %{query | term: nil}

  def search(%__MODULE__{} = query, term) when is_binary(term) do
    case String.trim(term) do
      "" -> %{query | term: nil}
      term -> %{query | term: term}
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
  The parameters a search is carried by: the facets, the term, and the mode it searches
  within where that is not Everything.
  """
  @spec search_params(t()) :: %{String.t() => String.t()}
  def search_params(%__MODULE__{} = query) do
    query
    |> to_params()
    |> then(&if query.term, do: Map.put(&1, "q", query.term), else: &1)
    |> then(&if query.mode == "everything", do: &1, else: Map.put(&1, "in", query.mode))
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

  Each narrowing is removable on its own, so this takes the one value
  rather than the axis: a surface narrowed to two decades and one category loses the
  decade a person dismisses and keeps the other.
  """
  @spec widen(t(), String.t(), String.t()) :: t()
  def widen(%__MODULE__{} = query, axis, value) do
    put(query, axis, List.delete(Map.get(query.facets, axis, []), value))
  end

  @doc """
  The same mode with nothing narrowing it.

  What a narrowed surface counts against to say how much of the whole it is showing.
  """
  @spec unnarrowed(t()) :: t()
  def unnarrowed(%__MODULE__{} = query), do: %{query | facets: %{}, term: nil}

  @doc """
  The same query with one axis carrying nothing.

  What a facet's own counts are computed over. The count beside a value is what selecting
  it will hold, and selecting it widens its own axis rather than replacing the query, so
  the axis's own narrowing comes off and goes back on one value at a time.
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
  def narrowed?(%__MODULE__{} = query), do: narrowings(query) != [] or query.term != nil

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

  defp admissible(_values, axis) when axis not in @narrowable do
    {:error, {:inert_axis, axis}}
  end

  defp admissible(values, _identifiers), do: {:ok, values}
end
