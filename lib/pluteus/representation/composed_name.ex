defmodule Pluteus.Representation.ComposedName do
  @moduledoc """
  What a surface shows for a res that resolution returns no displayable name for
  ([spec-10] §6.3).

  spec-01 §4.1 makes the primary identifier a nomen and §7.4 forbids falling back
  to it, so a res whose only nomen is that identifier-nomen, or whose nomens the
  profile excludes, satisfies LRM-R13 and still has nothing to show. Every reified
  address and every annotation is in that position by construction (spec-01 §6.1),
  and those outnumber every other row class.

  The name is composed from what the res is related to and from its kind:

      A photograph, at Bridgeport, with Eleanor and Thomas, in July 2009.

  **Its terminal is a noun for the res's kind**, which is always available because
  kind is a non-null property of every res. The clauses before it are omitted as
  their relations are absent, so the composition degrades rather than failing.

  A composed name is not a nomen. It is never written to the catalog, and it never
  appears among the nomens a representation carries. It is also the accessible name
  for the same res, so one string serves both.

  §8.5 forbids the model's own vocabulary as a label, so the nouns here say what a
  person would say. §7 asks that the interface's own words follow the requesting
  principal's language where a translation exists; that is the interface's to do,
  and these are the words it translates.
  """

  alias Pluteus.Annotations.Annotation
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Credit
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Catalog.WorkCreator
  alias Pluteus.Ingest.Place
  alias Pluteus.Repo

  import Ecto.Query, only: [from: 2]

  # spec-04 §6.3's categories, said the way a person says them.
  @category_nouns %{
    "album" => "a release",
    "music_recording" => "a recording",
    "audiobook" => "an audiobook",
    "podcast_episode" => "a podcast episode",
    "film" => "a film",
    "television_episode" => "an episode",
    "home_video" => "a home video",
    "photograph" => "a photograph",
    "scan" => "a scan",
    "document" => "a document",
    "ebook" => "an ebook",
    "comic_issue" => "a comic issue",
    "video_game" => "a game",
    "cover_art" => "a cover",
    "lyrics" => "a lyric file",
    "subtitles" => "a subtitle track",
    "cue_sheet" => "a cue sheet",
    "description" => "a description",
    "metadata" => "a metadata file"
  }

  # Every kind a res may take. The five structural entities share one noun,
  # because §8.5 forbids the words that would tell them apart and a person does
  # not draw the distinction anyway.
  @kind_nouns %{
    res: "a thing",
    work: "a holding",
    expression: "a holding",
    manifestation: "a holding",
    item: "a holding",
    digital_item: "a holding",
    asset: "a file",
    person: "a person",
    collective_agent: "a group",
    artist: "an artist",
    nomen: "a name",
    place: "a place",
    time_span: "a period of time",
    address: "a region",
    annotation: "a note"
  }

  @doc """
  A composed name for each of the given res, keyed by identifier.

  The agents every res is related to are named in one pass, so composing a page of
  them costs a bounded number of queries however many there are.
  """
  @spec for_many([Res.t()], Profile.t()) :: %{Ecto.UUID.t() => String.t()}
  def for_many([], _profile), do: %{}

  def for_many(res_list, %Profile{} = profile) do
    works = Map.new(res_list, &{&1.id, Catalog.work_of(&1.id)})
    agents = agents_of(works)
    targets = targets_of(res_list)

    named =
      Resolution.resolve_many(
        Enum.uniq(List.flatten(Map.values(agents)) ++ Map.values(targets)),
        profile
      )

    Map.new(res_list, fn res ->
      {res.id, compose(res, works[res.id], Map.get(agents, res.id, []), targets[res.id], named)}
    end)
  end

  @doc """
  A composed name for one res.
  """
  @spec for_one(Res.t(), Profile.t()) :: String.t()
  def for_one(%Res{} = res, %Profile{} = profile),
    do: Map.fetch!(for_many([res], profile), res.id)

  @doc """
  The noun a res's kind is said by, which is the terminal §6.3 requires always be
  available.
  """
  @spec noun(atom()) :: String.t()
  def noun(kind), do: Map.fetch!(@kind_nouns, kind)

  defp compose(%Res{kind: kind} = res, work_id, agent_ids, target_id, named)
       when kind in [:address, :annotation] do
    # A region and a note are identified by what they are about, so the thing they
    # are about is the clause that carries them.
    about =
      case named[target_id] do
        nil -> nil
        nomen -> nomen.nomen_string
      end

    [preposition(kind), about]
    |> clause(head(res, work_id))
    |> with_agents(agent_ids, named)
    |> sentence()
  end

  defp compose(%Res{} = res, work_id, agent_ids, _target_id, named) do
    res
    |> head(work_id)
    |> with_agents(agent_ids, named)
    |> sentence()
  end

  # The head is the category's noun where the res has one, and its kind's
  # otherwise. §6.3's example opens "A photograph", which is the category.
  defp head(%Res{kind: kind} = res, work_id) do
    category = category_of(res, work_id)

    Map.get(@category_nouns, category) || noun(kind)
  end

  defp category_of(%Res{id: id}, nil), do: Catalog.category_of(id, Place.category_scheme())
  defp category_of(_res, work_id), do: Catalog.category_of(work_id, Place.category_scheme())

  defp preposition(:address), do: "of"
  defp preposition(:annotation), do: "on"

  defp clause([_preposition, nil], head), do: head
  defp clause([preposition, about], head), do: "#{head} #{preposition} #{about}"

  defp with_agents(head, [], _named), do: head

  defp with_agents(head, agent_ids, named) do
    names =
      agent_ids
      |> Enum.map(&named[&1])
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.nomen_string)
      |> Enum.uniq()

    # An agent that resolves to nothing itself is left out rather than described:
    # one composed name inside another says less than the clause it replaced.
    case names do
      [] -> head
      names -> "#{head}, with #{join(names)}"
    end
  end

  defp join([one]), do: one
  defp join([one, two]), do: "#{one} and #{two}"

  defp join(names) do
    {leading, [last]} = Enum.split(names, -1)

    "#{Enum.join(leading, ", ")} and #{last}"
  end

  # Only the first character rises. The rest is left as it stands, because most of
  # a composed name is proper nouns carrying their own case.
  defp sentence(<<first::utf8, rest::binary>>),
    do: String.upcase(<<first::utf8>>) <> rest <> "."

  # A work's creators and the agents credited on it, which is what §6.3 reaches
  # for. Both are gathered for the whole page at once.
  defp agents_of(works) do
    work_ids = works |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.uniq()

    creators =
      Repo.all(
        from c in WorkCreator,
          where: c.work_id in ^work_ids,
          order_by: c.agent_id,
          select: {c.work_id, c.agent_id}
      )

    credits =
      Repo.all(
        from c in Credit,
          where: c.work_id in ^work_ids and not is_nil(c.agent_id),
          order_by: [c.role, c.position],
          select: {c.work_id, c.agent_id}
      )

    by_work = Enum.group_by(creators ++ credits, &elem(&1, 0), &elem(&1, 1))

    Map.new(works, fn {res_id, work_id} ->
      {res_id, by_work |> Map.get(work_id, []) |> Enum.uniq()}
    end)
  end

  defp targets_of(res_list) do
    for %Res{kind: kind, id: id} <- res_list, kind in [:address, :annotation], into: %{} do
      {id, target_of(kind, id)}
    end
  end

  defp target_of(:address, id), do: Catalog.get_address(id).target_id

  defp target_of(:annotation, id),
    do: Repo.one(from a in Annotation, where: a.id == ^id, select: a.target_id)
end
