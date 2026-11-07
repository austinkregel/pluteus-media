defmodule Pluteus.Matching.Music do
  @moduledoc """
  Which recording, track, release, release group and work a piece of music is, from the
  identifiers it carries and the MusicBrainz copy the household holds (spec-05 §9.1), in
  spec-05 §7's stages.

    * **Key** reads each placed track's MusicBrainz identifiers and ISRCs
      (`Pluteus.Matching.MusicKeys`), and a release ripped to one file the disc ID its
      cue sheet's table of contents hashes to, and records each on a match record about
      the res its scheme identifies (§4.1): the recording's expression, the track's
      manifestation, the work, the release's manifestation, the release's work and the
      medium. A scheme a holding carries nothing for is recorded empty, so it is not read
      again on every pass, and a scheme added later finds every holding due by the same
      query (§7.1).
    * **Resolve** answers each keyed record from the snapshot in use, recording what the
      corpus holds for each identifier, unaltered. A corpus holding nothing for one is
      silent (§5.2), and the record is empty. A newer snapshot makes every record resolved
      from an older one due again, as a successor that supersedes it (§6.5, §8.7).
    * **Apply** writes each identifier the corpus holds as a nomen at the level its scheme
      identifies, assigned by MusicBrainz (§8.2), and equates two expressions or two works
      found carrying one (§8.4, `Pluteus.Matching.Equation`). An ISRC the corpus gives to
      exactly one recording yields that recording's identifier; a disc ID the corpus
      attaches to exactly one medium yields its release's identifier and, by position,
      each of its tracks' recordings. An identifier a member wrote on a res is never
      replaced (§8.7).

  Nothing here asks anyone outside the house, runs inside placement's transaction, or runs
  because someone looked at anything (§14). Catalog writes are the System principal's.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Actor
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.ManifestationPart
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Corpus
  alias Pluteus.Corpus.Discography
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Finding
  alias Pluteus.Ingest.Place
  alias Pluteus.Lifecycle
  alias Pluteus.Matching.Equation
  alias Pluteus.Matching.MatchRecord
  alias Pluteus.Matching.MusicKeys
  alias Pluteus.Matching.Registry
  alias Pluteus.Matching.Sources
  alias Pluteus.Principals
  alias Pluteus.Repo

  @corpus "musicbrainz"

  # The res each scheme identifies, for a holding that is one track and for one that is a
  # whole release ripped to one file. A release's own file carries the release's
  # identifiers and not its tracks'.
  @track_schemes %{
    "musicbrainz_recording" => :recording,
    "isrc" => :recording,
    "musicbrainz_track" => :track,
    "musicbrainz_work" => :work,
    "musicbrainz_release" => :release,
    "musicbrainz_release_group" => :release_work,
    "musicbrainz_disc" => :medium
  }

  @release_schemes %{
    "musicbrainz_release" => :release,
    "musicbrainz_release_group" => :release_work,
    "musicbrainz_disc" => :medium
  }

  # --- Key ------------------------------------------------------------------------------

  @doc """
  Keys every placed piece of music some scheme of which has no current MusicBrainz match
  record about the res it identifies, and no open matching finding, up to `limit` of them.
  """
  @spec key_due(pos_integer()) :: [{Ecto.UUID.t(), term()}]
  def key_due(limit \\ 200) do
    holdings = holdings()
    keyed = current(Enum.flat_map(holdings, &Map.values(&1.targets)))

    {due, _keyed} =
      Enum.reduce(holdings, {[], keyed}, fn holding, {due, keyed} ->
        missing = Enum.reject(holding.targets, &MapSet.member?(keyed, swap(&1)))

        if missing == [] or length(due) >= limit,
          do: {due, keyed},
          else: {[{holding, missing} | due], MapSet.union(keyed, MapSet.new(missing, &swap/1))}
      end)

    due
    |> Enum.reverse()
    |> Enum.map(fn {holding, missing} ->
      {holding.asset_id,
       Ingest.isolated(:match, %{acquisition_id: holding.asset_id}, fn ->
         key(holding, missing)
       end)}
    end)
  end

  defp swap({scheme, res}), do: {res, scheme}

  # Every placed piece of music that is live, with the res each scheme identifies for it.
  defp holdings do
    tracks =
      Repo.all(
        from a in Acquisition,
          join: s in Asset,
          on: s.id == a.id,
          join: d in DigitalItem,
          on: d.id == a.digital_item_id,
          join: medium in ManifestationPart,
          on: medium.part_id == d.manifestation_id,
          join: release in ManifestationPart,
          on: release.part_id == medium.whole_id,
          join: e in Embodiment,
          on: e.manifestation_id == d.manifestation_id,
          join: x in Expression,
          on: x.id == e.expression_id,
          join: re in Embodiment,
          on: re.manifestation_id == release.whole_id,
          join: rx in Expression,
          on: rx.id == re.expression_id,
          where: a.state == :placed and a.media_class == :audio,
          where: a.id not in subquery(blocked()),
          order_by: a.id,
          select: %{
            asset_id: a.id,
            location: s.location,
            kind: :track,
            manifestation: d.manifestation_id,
            res: %{
              recording: x.id,
              track: d.manifestation_id,
              work: x.work_id,
              medium: medium.whole_id,
              release: release.whole_id,
              release_work: rx.work_id
            }
          }
      )

    releases =
      Repo.all(
        from a in Acquisition,
          join: s in Asset,
          on: s.id == a.id,
          join: d in DigitalItem,
          on: d.id == a.digital_item_id,
          join: medium in ManifestationPart,
          on: medium.whole_id == d.manifestation_id,
          join: re in Embodiment,
          on: re.manifestation_id == d.manifestation_id,
          join: rx in Expression,
          on: rx.id == re.expression_id,
          where: a.state == :placed and a.media_class == :audio,
          where: a.id not in subquery(blocked()),
          order_by: a.id,
          select: %{
            asset_id: a.id,
            location: s.location,
            kind: :release,
            manifestation: d.manifestation_id,
            res: %{
              medium: medium.part_id,
              release: d.manifestation_id,
              release_work: rx.work_id
            }
          }
      )

    held = tracks ++ releases
    live = Lifecycle.live_among(Enum.map(held, & &1.manifestation))

    for holding <- held, MapSet.member?(live, holding.manifestation) do
      schemes = if holding.kind == :track, do: @track_schemes, else: @release_schemes

      Map.put(
        holding,
        :targets,
        Map.new(schemes, fn {scheme, at} -> {scheme, holding.res[at]} end)
      )
    end
  end

  defp current(res_ids) do
    Repo.all(
      from m in MatchRecord,
        where: m.source == @corpus and is_nil(m.superseded_by_id) and m.res_id in ^res_ids,
        select: {m.res_id, m.scheme}
    )
    |> MapSet.new()
  end

  # spec-05 §12: a holding carrying an open matching finding is out of due work until a
  # person clears it.
  defp blocked do
    from f in Finding,
      where: f.stage == :match and is_nil(f.cleared_at) and not is_nil(f.acquisition_id),
      select: f.acquisition_id
  end

  defp key(holding, missing) do
    acquisition = Repo.get!(Acquisition, holding.asset_id)

    with {:ok, carried} <- MusicKeys.carried(acquisition, holding.location),
         {:ok, disc} <- disc(holding, acquisition, Map.get(carried, "musicbrainz_disc", [])) do
      carried = Map.put(carried, "musicbrainz_disc", disc.values)
      for {scheme, res} <- missing, do: keyed(holding, res, scheme, carried, disc)
      :keyed
    else
      {:error, {kind, detail}} ->
        Ingest.record_finding(%{
          stage: :match,
          kind: kind,
          permanent: true,
          acquisition_id: holding.asset_id,
          detail: detail
        })

        :unkeyable
    end
  end

  defp keyed(holding, res, scheme, carried, disc) do
    case Map.get(carried, scheme, []) do
      [] -> record_key(holding.asset_id, res, scheme, %{}, :empty, unkeyed(scheme, disc))
      values -> record_key(holding.asset_id, res, scheme, query(scheme, values, disc), :keyed)
    end
  end

  # A release in one file is its disc's audio, and its cue sheet gives the disc's table of
  # contents; a disc ID a tagger wrote must agree with the one computed, or the evidence
  # contradicts itself.
  defp disc(%{kind: :track}, _acquisition, tagged), do: {:ok, %{values: tagged}}

  defp disc(%{kind: :release}, acquisition, tagged) do
    case Place.cue_sheet_for(acquisition) do
      nil -> {:ok, %{values: tagged, not_computable: "no_cue_sheet"}}
      cue -> computed(MusicKeys.disc(acquisition, cue), tagged)
    end
  end

  defp computed({:ok, %{toc: toc, discid: discid}}, tagged) do
    case Enum.uniq([discid | tagged]) do
      [^discid] ->
        {:ok, %{values: [discid], toc: toc}}

      several ->
        {:error,
         {"identifiers_contradict", %{"scheme" => "musicbrainz_disc", "values" => several}}}
    end
  end

  defp computed({:not_computable, reason}, tagged),
    do: {:ok, %{values: tagged, not_computable: to_string(reason)}}

  defp computed({:error, _unkeyable} = refused, _tagged), do: refused

  # What is asked of the corpus: the identifiers carried, and for a computed disc ID the
  # table of contents it was computed from.
  defp query("musicbrainz_disc", values, %{toc: toc}), do: %{"values" => values, "toc" => toc}
  defp query(_scheme, values, _disc), do: %{"values" => values}

  # Why nothing was asked: for a disc, what kept a table of contents from being computed.
  defp unkeyed("musicbrainz_disc", %{not_computable: reason}), do: %{"not_computable" => reason}
  defp unkeyed(_scheme, _disc), do: nil

  defp record_key(
         asset_id,
         res,
         scheme,
         query,
         state,
         conclusion \\ nil,
         record \\ %MatchRecord{}
       ) do
    record
    |> MatchRecord.keyed_changeset(%{
      res_id: res,
      asset_id: asset_id,
      scheme: scheme,
      source_kind: :corpus,
      source: @corpus,
      rank: "corpus",
      rank_order: Registry.rank_order(),
      query: query,
      state: state,
      conclusion: conclusion
    })
    |> Repo.insert!(
      on_conflict: :nothing,
      conflict_target:
        {:unsafe_fragment, "(res_id, scheme, source) WHERE superseded_by_id IS NULL"}
    )
  end

  # --- Resolve --------------------------------------------------------------------------

  @doc """
  Resolves keyed records against the MusicBrainz snapshot in use, first making a successor
  for every record resolved from an older one. With no snapshot imported nothing is due.
  """
  @spec resolve_due(pos_integer()) :: [{Ecto.UUID.t(), term()}]
  def resolve_due(limit \\ 200) do
    case Corpus.current(@corpus) do
      nil ->
        []

      snapshot ->
        succeed_stale(snapshot.stated_on, limit)

        Repo.all(
          from m in MatchRecord,
            where: m.source == @corpus and m.state == :keyed and is_nil(m.superseded_by_id),
            where: m.asset_id not in subquery(blocked()),
            order_by: m.id,
            limit: ^limit
        )
        |> Enum.map(fn record ->
          {record.id,
           Ingest.isolated(:match, %{acquisition_id: record.asset_id}, fn ->
             resolve(record, snapshot.stated_on)
           end)}
        end)
    end
  end

  defp succeed_stale(stated_on, limit) do
    stale =
      Repo.all(
        from m in MatchRecord,
          where: m.source == @corpus and is_nil(m.superseded_by_id),
          where: m.state in [:resolved, :applied, :candidate, :empty],
          where: not is_nil(m.snapshot_on) and m.snapshot_on < ^stated_on,
          order_by: m.id,
          limit: ^limit
      )

    for record <- stale do
      {:ok, _keyed} =
        Repo.transaction(fn ->
          successor = UUIDv7.generate()
          record |> MatchRecord.superseded_changeset(successor) |> Repo.update!()

          record_key(
            record.asset_id,
            record.res_id,
            record.scheme,
            record.query,
            :keyed,
            nil,
            %MatchRecord{id: successor}
          )
        end)
    end
  end

  defp resolve(record, stated_on) do
    answers = Map.new(record.query["values"], &{&1, answer(record.scheme, &1)})
    held = Enum.any?(Map.values(answers), &(&1 not in [nil, []]))

    record
    |> MatchRecord.resolved_changeset(%{
      response: %{"answers" => answers},
      basis: :equality,
      snapshot_on: stated_on,
      state: if(held, do: :resolved, else: :empty)
    })
    |> Repo.update!()
    |> Map.fetch!(:state)
  end

  defp answer("isrc", isrc), do: Discography.recordings_with_isrc(isrc)
  defp answer("musicbrainz_disc", discid), do: Discography.media_with_disc(discid)
  defp answer(scheme, mbid), do: Discography.identifier(scheme, mbid)

  # --- Apply ----------------------------------------------------------------------------

  @doc """
  Applies resolved records: writes the identifiers each answer holds, and performs the
  equations they license.
  """
  @spec apply_due(pos_integer()) :: [{Ecto.UUID.t(), term()}]
  def apply_due(limit \\ 200) do
    Repo.all(
      from m in MatchRecord,
        where: m.source == @corpus and m.state == :resolved and is_nil(m.superseded_by_id),
        where: m.asset_id not in subquery(blocked()),
        order_by: m.id,
        limit: ^limit
    )
    |> Enum.map(fn record ->
      {record.id,
       Ingest.isolated(:match, %{acquisition_id: record.asset_id}, fn -> apply_answer(record) end)}
    end)
  end

  defp apply_answer(record) do
    Actor.as(Principals.system!().id, fn ->
      {:ok, state} = Repo.transaction(fn -> conclude(record, Sources.agent!(@corpus)) end)
      state
    end)
  end

  defp conclude(%MatchRecord{scheme: "isrc"} = record, agent) do
    answers = record.response["answers"]
    held = for {isrc, [_ | _] = recordings} <- answers, do: {isrc, recordings}
    written = for {isrc, _} <- held, do: written(record.res_id, "isrc", isrc, agent)

    derived =
      held
      |> Enum.flat_map(fn
        {_isrc, [%{"mbid" => mbid}]} -> [mbid]
        {_isrc, _several} -> []
      end)
      |> Enum.uniq()

    case derived do
      [] ->
        finish(record, %{"written" => written, "equations" => []})

      [mbid] ->
        recording =
          written(record.res_id, "musicbrainz_recording", mbid, agent, {:through, record})

        finish(record, %{
          "written" => written ++ [Map.put(recording, "through", "isrc")],
          "equations" => equations_after(recording, record)
        })

      several ->
        contradicted!(record, "musicbrainz_recording", several)
        finish(record, %{"written" => written, "equations" => [], "contradicted" => several})
    end
  end

  defp conclude(%MatchRecord{scheme: "musicbrainz_disc"} = record, agent) do
    [{discid, media}] = Map.to_list(record.response["answers"])
    medium = record.res_id
    disc = written(medium, "musicbrainz_disc", discid, agent)

    case media do
      [one] ->
        {written, equations} = from_medium(medium, one, record, agent)
        finish(record, %{"written" => [disc | written], "equations" => equations})

      _several ->
        finish(record, %{"written" => [disc], "equations" => [], "media" => length(media)})
    end
  end

  defp conclude(record, agent) do
    [mbid] =
      record.response["answers"]
      |> Map.values()
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1["mbid"])
      |> Enum.uniq()

    written = written(record.res_id, record.scheme, mbid, agent)
    finish(record, %{"written" => [written], "equations" => equations_after(written, record)})
  end

  # The one medium a disc ID names: its release, and each of its tracks' recordings by
  # position, where the medium holds as many tracks as the disc's table of contents.
  defp from_medium(medium, held, record, agent) do
    through = {:through, record}
    [%{whole_id: release}] = Catalog.wholes_of(medium)
    release = written(release, "musicbrainz_release", held["release"]["mbid"], agent, through)
    parts = Catalog.parts_of(medium)

    if length(parts) == length(held["tracks"]) do
      by_position = Map.new(held["tracks"], &{&1["position"], &1["recording"]["mbid"]})

      {written, equations} =
        parts
        |> Enum.map(fn part ->
          [expression] = Catalog.expressions_in(part.part_id)
          mbid = Map.fetch!(by_position, part.position)
          recording = written(expression.id, "musicbrainz_recording", mbid, agent, through)
          {recording, equations_after(recording, record)}
        end)
        |> Enum.unzip()

      {[release | written], List.flatten(equations)}
    else
      {[release], []}
    end
  end

  # An identifier the res did not take — one contradicting what it carries, or one a
  # member settled otherwise — licenses no equation.
  defp equations_after(%{"outcome" => outcome} = written, record)
       when outcome in ["written", "replaced", "held"],
       do: equations(written["res"], written["scheme"], written["value"], record)

  defp equations_after(_not_taken, _record), do: []

  defp finish(record, conclusion) do
    record
    |> MatchRecord.concluded_changeset(%{state: :applied, conclusion: conclusion})
    |> Repo.update!()
    |> Map.fetch!(:state)
  end

  # §8.2: an identifier is a nomen in its scheme, assigned by the agent that issues it,
  # which for every scheme here is MusicBrainz. A res already carrying it is left as it
  # is, and one carrying another a member wrote keeps the member's (§8.7). One carrying
  # another an earlier answer about its own key wrote has it replaced, the later answer
  # superseding (§6.5), unless the scheme allows several.
  #
  # A value reached through another identifier — a recording through an ISRC, a release
  # through a disc ID — is a second source for the res, and one disagreeing with what the
  # res already carries is a contradiction (§5.4): neither is written over, and it is a
  # finding.
  defp written(res, scheme, value, agent, reached \\ :directly) do
    existing = Repo.all(from n in Nomen, where: n.res_id == ^res and n.scheme == ^scheme)
    outcome = outcome(existing, value, Registry.several?(scheme), reached)

    case outcome do
      "written" ->
        create_identifier!(res, scheme, value, agent)

      "replaced" ->
        Repo.delete_all(from n in Nomen, where: n.id in ^Enum.map(existing, & &1.id))
        create_identifier!(res, scheme, value, agent)

      "contradicted" ->
        {:through, record} = reached
        contradicted!(record, scheme, [value | Enum.map(existing, & &1.nomen_string)])

      _held_or_settled ->
        :unchanged
    end

    %{"res" => res, "scheme" => scheme, "value" => value, "outcome" => outcome}
  end

  defp outcome(existing, value, several, reached) do
    cond do
      Enum.any?(existing, &(&1.nomen_string == value)) -> "held"
      several -> "written"
      Enum.any?(existing, &(&1.provenance != :automatic)) -> "settled"
      existing != [] and reached != :directly -> "contradicted"
      existing != [] -> "replaced"
      true -> "written"
    end
  end

  defp create_identifier!(res, scheme, value, agent) do
    {:ok, _} =
      Catalog.create_nomen(%{
        res_id: res,
        nomen_string: value,
        scheme: scheme,
        provenance: :automatic,
        assigner_id: agent
      })
  end

  # §8.4 and §4.3: two expressions carrying one recording identifier are one expression,
  # which makes their works one; two works carrying one work or release group identifier
  # are one work. An identifier of a manifestation equates nothing here.
  defp equations(res, scheme, value, record) do
    case level(Registry.level(scheme)) do
      nil ->
        []

      level ->
        others =
          scheme
          |> Catalog.nomens_by_external_identifier(value)
          |> Enum.map(& &1.res_id)
          |> Enum.reject(&(&1 == res))
          |> Lifecycle.live_among()
          |> Enum.sort()

        for other <- others do
          {outcome, detail} =
            Equation.equate(res, other, level, %{"scheme" => scheme, "value" => value}, record)

          Map.put(detail, "outcome", Atom.to_string(outcome))
        end
    end
  end

  defp level("expression"), do: :same_expression
  defp level("work"), do: :same_work
  defp level("aggregating_work"), do: :same_work
  defp level(_manifestation), do: nil

  defp contradicted!(record, scheme, values) do
    Ingest.record_finding(%{
      stage: :match,
      kind: "identifiers_contradict",
      permanent: true,
      acquisition_id: record.asset_id,
      detail: %{"scheme" => scheme, "values" => values, "match_record" => record.id}
    })
  end
end
