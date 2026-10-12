defmodule Pluteus.Serials do
  @moduledoc """
  What a serial work gathers, as the surface listing it reads ([spec-10] §8.4, §12.1).

  spec-01 §5.4 puts the two halves of a serial at different levels: an issue's work is
  connected to the serial's work by inspiration, and where it sits is an arrangement of
  the serial's own manifestation rather than a property of the issue. The order here is
  therefore the arrangement's, and a member the serial does not number follows the ones
  it does rather than being given a number to sort by.

  A member the household does not hold is a member all the same. §5.2 makes *not held* a
  state of a res the catalog records, and a list that left those out would show a run of
  episodes with no gap in it — the gap is the thing a person is looking for.

  What a principal has watched is that principal's own (§14.3), so it is read for the one
  asking and never composed across the household.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Extent
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Refinements
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Events
  alias Pluteus.Ingest.Place
  alias Pluteus.Ingest.Registry, as: Formats
  alias Pluteus.Lifecycle.RecycledRes
  alias Pluteus.Lifecycle.Tombstone
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Registry
  alias Pluteus.Repo
  alias Pluteus.Representation.ComposedName

  @typedoc """
  One member of a serial, as a surface lists it.
  """
  @type member :: %{
          work_id: Ecto.UUID.t() | nil,
          manifestation_id: Ecto.UUID.t(),
          category: String.t() | nil,
          position: pos_integer() | nil,
          name: String.t(),
          named?: boolean(),
          held?: boolean(),
          issued: String.t() | nil,
          extent_ms: non_neg_integer() | nil,
          poster?: boolean(),
          resumed_ms: non_neg_integer() | nil,
          watched?: boolean()
        }

  @doc """
  The members of a serial work, in the order its manifestation arranges them.

  An empty list for a work that is not a serial. Every whole arranges something on its
  manifestation and only a serial arranges its members there: a release arranges the
  media it was pressed on, and a medium is not a track — a list of them would report
  every disc of a set as a thing the household does not hold.
  """
  @spec members(Ecto.UUID.t(), Ecto.UUID.t(), Profile.t()) :: [member()]
  def members(work_id, principal_id, %Profile{} = profile) do
    with true <- serial?(work_id),
         manifestation when is_binary(manifestation) <- gathering(work_id) do
      gathered(manifestation, principal_id, profile)
    else
      _not_a_serial_or_nothing_embodies_it -> []
    end
  end

  @doc """
  Whether a work is a serial: one that gathers issues of itself (spec-01 §5.4).
  """
  @spec serial?(Ecto.UUID.t()) :: boolean()
  def serial?(work_id) do
    Catalog.category_of(work_id, Place.category_scheme()) in Formats.serial_categories()
  end

  @doc """
  The manifestation a serial work arranges its members on, or nil.
  """
  @spec gathering(Ecto.UUID.t()) :: Ecto.UUID.t() | nil
  def gathering(work_id) do
    with [expression | _rest] <- Catalog.expressions_of(work_id),
         [manifestation | _more] <- Catalog.manifestations_of(expression.id) do
      manifestation.id
    else
      _nothing_embodies_it -> nil
    end
  end

  defp gathered(manifestation_id, principal_id, profile) do
    parts = Catalog.parts_of(manifestation_id)
    ids = Enum.map(parts, & &1.part_id)

    works = Catalog.works_of_many(ids)
    names = named(ids, works, profile)
    categories = categories(works)
    held = held(ids)
    issued = issued(ids)
    extents = extents(ids)
    posters = Presentation.for_subjects(ids, Map.fetch!(Registry.key_frame(), "name"))
    resumed = resumed(principal_id)
    watched = Events.plays(principal_id, ids, "played")

    for part <- parts do
      id = part.part_id

      %{
        work_id: works[id],
        manifestation_id: id,
        category: categories[works[id]],
        position: part.position,
        name: Map.fetch!(names, id).said,
        named?: Map.fetch!(names, id).named?,
        held?: MapSet.member?(held, id),
        issued: issued[id],
        extent_ms: extents[id],
        poster?: Map.has_key?(posters, id),
        resumed_ms: resumed[id],
        watched?: Map.get(watched, id, 0) > 0
      }
    end
  end

  # What each member is, so a surface listing them can send a person where that kind of
  # holding is presented. One query for the whole list, since a category is recorded on
  # the work and every member has one.
  defp categories(works) do
    ids = works |> Map.values() |> Enum.uniq()
    scheme = Place.category_scheme()

    for {work_id, categories} <- Catalog.categories_of_many(ids),
        effective = effective(categories, scheme),
        into: %{} do
      {work_id, effective}
    end
  end

  # A member's correction over an automatic assignment over a seeded one (§7.5), which is
  # what `Catalog.category_of/2` answers for one res: taking whichever row came back first
  # would say a corrected holding is still what placement guessed.
  defp effective(categories, scheme) do
    categories
    |> Enum.filter(&(&1.scheme == scheme))
    |> Enum.min_by(&rank/1, fn -> nil end)
    |> value()
  end

  defp rank(category),
    do: Enum.find_index(Nomen.provenance_rank(), &(&1 == category.provenance))

  defp value(nil), do: nil
  defp value(category), do: category.value

  # A member is named by its own work where it has one, since that is what a person
  # follows, and by §6.3's composed name where resolution answers none. Which of the two
  # it was is carried, because §5.2 has the surface say that a name is absent rather than
  # presenting a composed one as though the thing were called that.
  defp named([], _works, _profile), do: %{}

  defp named(ids, works, profile) do
    subjects = Map.new(ids, fn id -> {id, works[id] || id} end)
    resolved = subjects |> Map.values() |> Resolution.resolve_many(profile)
    unnamed = for {_id, subject} <- subjects, not Map.has_key?(resolved, subject), do: subject
    composed = ComposedName.for_many(Repo.all(from r in Res, where: r.id in ^unnamed), profile)

    Map.new(subjects, fn {id, subject} ->
      case resolved[subject] do
        nil -> {id, %{said: Map.fetch!(composed, subject), named?: false}}
        nomen -> {id, %{said: nomen.nomen_string, named?: true}}
      end
    end)
  end

  # Held is carrying a file. A manifestation the catalog records and the household has no
  # digital item for is the §5.2 state the gap in a run of episodes is made of.
  defp held([]), do: MapSet.new()

  defp held(ids) do
    MapSet.new(
      Repo.all(
        from d in DigitalItem,
          where: d.manifestation_id in ^ids,
          where: d.id not in subquery(from r in RecycledRes, select: r.res_id),
          where: d.id not in subquery(from t in Tombstone, select: t.res_id),
          select: d.manifestation_id
      )
    )
  end

  defp issued([]), do: %{}

  defp issued(ids) do
    refinement = Refinements.name!("time-of-publication-or-manufacture")

    Map.new(
      Repo.all(
        from a in Association,
          join: n in Nomen,
          on: n.res_id == a.object_id and is_nil(n.assigner_id),
          where: a.subject_id in ^ids and a.refinement == ^refinement,
          order_by: [asc: a.subject_id, asc: n.id],
          select: {a.subject_id, n.nomen_string}
      )
    )
  end

  defp extents([]), do: %{}

  defp extents(ids) do
    Map.new(
      Repo.all(
        from x in Extent,
          where: x.res_id in ^ids and x.unit == :millisecond,
          select: {x.res_id, x.magnitude}
      )
    )
  end

  # §13.3's positions for the one asking, which is the only principal any of this reads.
  defp resumed(principal_id) do
    Map.new(Events.resumable(principal_id), fn position ->
      {position.res_id, position.position}
    end)
  end
end
