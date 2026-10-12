defmodule Pluteus.Listening do
  @moduledoc """
  A reading as the surface it is listened to on reads it ([spec-10] §12.1).

  A chapter is a region of the reading and not a holding of its own (spec-04 §6.9), so it
  is a temporal address on the manifestation: no work, no manifestation, no digital item.
  Placement records what the container declared and nothing else, so a reading whose
  container declares none has none, and this answers with none rather than dividing it
  somewhere this deployment chose.

  A chapter the container titled is named by that title. One it did not is named by
  §6.3's composed name, which terminates in a noun — never in a number made up here.

  Who a reading credits is two facts and not one: spec-04 §6.9 credits the author on the
  text and the narrator on the reading of it, which is why a credit is read here from
  both levels and kept in its role rather than flattened into a list of names.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Credit
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Repo
  alias Pluteus.Representation.ComposedName

  @typedoc """
  One chapter: where it begins and ends in the whole reading, and what it is called.
  """
  @type chapter :: %{
          id: Ecto.UUID.t(),
          name: String.t(),
          start_ms: non_neg_integer(),
          end_ms: non_neg_integer()
        }

  @doc """
  The chapters of one reading, in the order they are read in.

  Ordered by where each begins, because the order a container declares them in is the
  container's and a list a person reads along has to be the reading's.
  """
  @spec chapters(Ecto.UUID.t(), Profile.t()) :: [chapter()]
  def chapters(manifestation_id, %Profile{} = profile) do
    regions =
      manifestation_id
      |> Catalog.addresses_of()
      |> Enum.filter(&(&1.selector_type == :temporal))
      |> Enum.sort_by(& &1.start_ms)

    names = named(regions, profile)

    for %Address{} = region <- regions do
      %{
        id: region.id,
        name: Map.fetch!(names, region.id),
        start_ms: region.start_ms,
        end_ms: region.end_ms
      }
    end
  end

  @doc """
  Who the reading credits, in each role it credits them in.

  A role nobody is credited in is absent rather than present and empty, and an agent
  credited twice in one role is named once.
  """
  @spec credited(Ecto.UUID.t(), Profile.t()) :: [%{role: atom(), names: [String.t()]}]
  def credited(work_id, %Profile{} = profile) do
    credits =
      Repo.all(
        from c in Credit,
          left_join: x in Expression,
          on: x.id == c.expression_id,
          where: c.work_id == ^work_id or x.work_id == ^work_id,
          order_by: [asc: c.role, asc: c.position, asc: c.id]
      )

    names = credits |> Enum.map(& &1.agent_id) |> Resolution.resolve_many(profile)

    for role <- credits |> Enum.map(& &1.role) |> Enum.uniq() do
      %{role: role, names: in_role(credits, role, names)}
    end
  end

  @doc """
  Where each chapter begins, for a surface drawing them against a length.
  """
  @spec starts([chapter()]) :: [map()]
  def starts(chapters), do: for(chapter <- chapters, do: %{"start_ms" => chapter.start_ms})

  defp in_role(credits, role, names) do
    credits
    |> Enum.filter(&(&1.role == role))
    |> Enum.map(&names[&1.agent_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.nomen_string)
    |> Enum.uniq()
  end

  # The name the container gave, where it gave one, and §6.3's composed name where it
  # did not. Both are resolved for the whole list at once, since a reading of forty
  # chapters is forty names and not forty queries.
  defp named([], _profile), do: %{}

  defp named(regions, profile) do
    ids = Enum.map(regions, & &1.id)
    resolved = Resolution.resolve_many(ids, profile)
    unnamed = Enum.reject(ids, &Map.has_key?(resolved, &1))
    composed = ComposedName.for_many(Repo.all(from r in Res, where: r.id in ^unnamed), profile)

    Map.new(ids, fn id ->
      case resolved[id] do
        nil -> {id, Map.fetch!(composed, id)}
        nomen -> {id, nomen.nomen_string}
      end
    end)
  end
end
