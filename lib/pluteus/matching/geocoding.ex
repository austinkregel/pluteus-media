defmodule Pluteus.Matching.Geocoding do
  @moduledoc """
  Where a photograph was taken, from the position its EXIF states and the gazetteer the
  household holds (spec-05 §9.7), in spec-05 §7's stages.

    * **Key** reads a placed image's position and records it on a match record. One
      carrying none is recorded empty, having asked nothing, so its bytes are not read
      again. One whose position was written and cannot be read is a finding.
    * **Resolve** answers a keyed record from the GeoNames snapshot in use, recording the
      nearest places and the divisions and countries they name, unaltered. A newer
      snapshot makes every record resolved from an older one due again, as a successor
      that supersedes it (§6.5, §8.7).
    * **Apply** writes what the answer supports (`Pluteus.Matching.Places`): the place
      recorded, with the places containing it, as the work's place of capture, and the
      finer place as a candidate. An earlier answer's place of capture is replaced; one a
      member asserted is never touched, and settles the matter (§3.2, §8.7).

  Nothing here asks anyone outside the house (criterion 31), runs inside placement's
  transaction, or runs because someone looked at anything (§14): each stage is a
  scheduled pass finding its own due work. Catalog writes are the System principal's.

  The match is about the work, because a place of capture is where the photograph was
  made rather than where a copy of it is kept; the key names the asset it was read from
  (criterion 14).
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Actor
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Refinements
  alias Pluteus.Corpus
  alias Pluteus.Corpus.Gazetteer
  alias Pluteus.Dedup.Candidate
  alias Pluteus.Exif
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Finding
  alias Pluteus.Matching.MatchRecord
  alias Pluteus.Matching.PlaceKey
  alias Pluteus.Matching.Places
  alias Pluteus.Matching.Registry
  alias Pluteus.Matching.Sources
  alias Pluteus.Principals
  alias Pluteus.Repo
  alias Pluteus.Storage

  @corpus "geonames"
  @scheme "geonames"

  # --- Key ------------------------------------------------------------------------------

  @doc """
  Keys every placed image whose work has no current GeoNames match record and no open
  matching finding, up to `limit` of them.
  """
  @spec key_due(pos_integer()) :: [{Ecto.UUID.t(), term()}]
  def key_due(limit \\ 200) do
    limit
    |> due_holdings()
    |> Enum.map(fn holding ->
      {holding.asset_id,
       Ingest.isolated(:match, %{acquisition_id: holding.asset_id}, fn -> key(holding) end)}
    end)
  end

  defp due_holdings(limit) do
    current =
      from m in MatchRecord,
        where: m.scheme == @scheme and m.source == @corpus and is_nil(m.superseded_by_id),
        select: m.res_id

    Repo.all(
      from a in Acquisition,
        join: s in Asset,
        on: s.id == a.id,
        join: d in DigitalItem,
        on: d.id == a.digital_item_id,
        join: e in Embodiment,
        on: e.manifestation_id == d.manifestation_id,
        join: x in Expression,
        on: x.id == e.expression_id,
        where: a.state == :placed and a.media_class == :image,
        where: x.work_id not in subquery(current),
        where: a.id not in subquery(blocked()),
        distinct: x.work_id,
        order_by: [x.work_id, a.id],
        limit: ^limit,
        select: %{work_id: x.work_id, asset_id: a.id, location: s.location}
    )
  end

  # spec-05 §12: a holding carrying an open matching finding is out of due work until a
  # person clears it.
  defp blocked do
    from f in Finding,
      where: f.stage == :match and is_nil(f.cleared_at) and not is_nil(f.acquisition_id),
      select: f.acquisition_id
  end

  defp key(holding) do
    bytes = Storage.leading(holding.location, Exif.head_bytes())

    case Exif.position(bytes) do
      {:ok, position} ->
        record_key(holding, :keyed, %{
          "latitude" => position.latitude,
          "longitude" => position.longitude,
          "accuracy" => position.accuracy
        })

      :none ->
        record_key(holding, :empty, %{})

      {:error, unreadable} ->
        Ingest.record_finding(%{
          stage: :match,
          kind: "position_unreadable",
          permanent: true,
          acquisition_id: holding.asset_id,
          detail: %{"unreadable" => inspect(unreadable)}
        })

        :unreadable
    end
  end

  defp record_key(holding, state, query, record \\ %MatchRecord{}) do
    record
    |> MatchRecord.keyed_changeset(%{
      res_id: holding.work_id,
      asset_id: holding.asset_id,
      scheme: @scheme,
      source_kind: :corpus,
      source: @corpus,
      rank: "corpus",
      rank_order: Registry.rank_order(),
      query: query,
      state: state
    })
    |> Repo.insert!()
    |> Map.fetch!(:state)
  end

  # --- Resolve --------------------------------------------------------------------------

  @doc """
  Resolves keyed records against the GeoNames snapshot in use, first making a successor
  for every record resolved from an older one. With no snapshot imported nothing is due.
  """
  @spec resolve_due(pos_integer()) :: [{Ecto.UUID.t(), term()}]
  def resolve_due(limit \\ 200) do
    case Corpus.current(@corpus) do
      nil ->
        []

      snapshot ->
        succeed_stale(snapshot.stated_on, limit)

        limit
        |> keyed()
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
          where: m.source == @corpus and m.scheme == @scheme and is_nil(m.superseded_by_id),
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
            %{work_id: record.res_id, asset_id: record.asset_id},
            :keyed,
            record.query,
            %MatchRecord{id: successor}
          )
        end)
    end
  end

  defp keyed(limit) do
    Repo.all(
      from m in MatchRecord,
        where: m.source == @corpus and m.state == :keyed and is_nil(m.superseded_by_id),
        where: m.asset_id not in subquery(blocked()),
        order_by: m.id,
        limit: ^limit
    )
  end

  defp resolve(record, stated_on) do
    %{"latitude" => latitude, "longitude" => longitude} = record.query
    neighbours = Gazetteer.nearest(latitude, longitude, Registry.reverse_geocoding!(@corpus))

    response = %{
      "neighbours" => Enum.map(neighbours, &stringify/1),
      "regions" => named(neighbours, &region_code/1, &region_named/1),
      "countries" => named(neighbours, & &1.country_code, &Gazetteer.country/1)
    }

    record
    |> MatchRecord.resolved_changeset(%{
      response: response,
      basis: :resemblance,
      snapshot_on: stated_on,
      state: if(neighbours == [], do: :empty, else: :resolved)
    })
    |> Repo.update!()
    |> Map.fetch!(:state)
  end

  defp region_code(%{country_code: country, admin1_code: admin1})
       when is_binary(country) and is_binary(admin1),
       do: country <> "." <> admin1

  defp region_code(_without_one), do: nil

  defp region_named(code) do
    [country, admin1] = String.split(code, ".", parts: 2)
    Gazetteer.region(country, admin1)
  end

  # What the gazetteer names each code the neighbours carry, or that it names nothing:
  # both are what the corpus answered, and both are recorded.
  defp named(neighbours, code, lookup) do
    neighbours
    |> Enum.map(code)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Map.new(fn key -> {key, key |> lookup.() |> stringify_named()} end)
  end

  defp stringify(neighbour),
    do: Map.new(neighbour, fn {key, value} -> {to_string(key), value} end)

  defp stringify_named(nil), do: nil
  defp stringify_named(named), do: stringify(named)

  # --- Apply ----------------------------------------------------------------------------

  @doc """
  Applies resolved records: writes what each answer supports, and raises the finer place.
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
      {:ok, state} = Repo.transaction(fn -> conclude(record) end)
      state
    end)
  end

  defp conclude(record) do
    work = record.res_id

    if settled?(work) do
      finish(record, :applied, %{
        "settled" => "a member asserted where this was taken",
        "recorded" => nil,
        "candidate" => nil,
        "replaced" => capture!(work, nil)
      })
    else
      answer =
        Places.answer(
          position(record.query),
          neighbours(record.response),
          Registry.reverse_geocoding!(@corpus)
        )

      agent = Sources.agent!(@corpus)
      recorded = answer.recorded && place!(answer.recorded, record.response, agent)
      replaced = capture!(work, recorded)
      candidate = answer.candidate && place!(answer.candidate, record.response, agent)
      if candidate, do: raise!(work, candidate, record)

      state =
        cond do
          recorded -> :applied
          candidate -> :candidate
          true -> :empty
        end

      finish(record, state, %{
        "recorded" => recorded,
        "candidate" => candidate,
        "replaced" => replaced
      })
    end
  end

  defp finish(record, state, conclusion) do
    record
    |> MatchRecord.concluded_changeset(%{state: state, conclusion: conclusion})
    |> Repo.update!()
    |> Map.fetch!(:state)
  end

  defp position(%{"latitude" => latitude, "longitude" => longitude, "accuracy" => accuracy}),
    do: %{latitude: latitude, longitude: longitude, accuracy: accuracy}

  # A neighbour whose division or country the gazetteer names nothing for carries none:
  # a code nothing names is no place to record.
  defp neighbours(%{"neighbours" => neighbours, "regions" => regions, "countries" => countries}) do
    Enum.map(neighbours, fn neighbour ->
      country = neighbour["country_code"]
      named_country = country && countries[country] && country

      region =
        named_country && neighbour["admin1_code"] &&
          regions["#{country}.#{neighbour["admin1_code"]}"]

      %{
        geonameid: neighbour["geonameid"],
        name: neighbour["name"],
        feature_code: neighbour["feature_code"],
        country_code: named_country,
        admin1_code: if(region, do: neighbour["admin1_code"]),
        metres: neighbour["metres"]
      }
    end)
  end

  # The place a decision names, made where it is not yet a res, with every place
  # containing it linked to it: a locality within its division, a division within its
  # country. Returned as what the conclusion records.
  defp place!({:locality, neighbour}, response, agent) do
    id = place_res!(neighbour.geonameid, neighbour.name, agent)

    containing =
      if neighbour.admin1_code do
        place!({:region, Map.take(neighbour, [:country_code, :admin1_code])}, response, agent)
      else
        neighbour.country_code &&
          place!({:country, %{country_code: neighbour.country_code}}, response, agent)
      end

    if containing, do: within!(id, containing["place_id"])
    concluded("locality", neighbour.geonameid, neighbour.name, id)
  end

  defp place!({:region, %{country_code: country, admin1_code: admin1}}, response, agent) do
    %{"geonameid" => geonameid, "name" => name} =
      Map.fetch!(response["regions"], "#{country}.#{admin1}")

    id = place_res!(geonameid, name, agent)
    containing = place!({:country, %{country_code: country}}, response, agent)
    within!(id, containing["place_id"])
    concluded("region", geonameid, name, id)
  end

  defp place!({:country, %{country_code: country}}, response, agent) do
    %{"geonameid" => geonameid, "name" => name} = Map.fetch!(response["countries"], country)
    concluded("country", geonameid, name, place_res!(geonameid, name, agent))
  end

  defp concluded(granularity, geonameid, name, id),
    do: %{
      "granularity" => granularity,
      "geonameid" => geonameid,
      "name" => name,
      "place_id" => id
    }

  # A place is one res however many photographs were taken in it. Its name and its
  # identifier are both GeoNames's, and GeoNames states no language for the name.
  defp place_res!(geonameid, name, agent) do
    case Repo.get(PlaceKey, geonameid) do
      %PlaceKey{place_id: id} ->
        id

      nil ->
        {:ok, place} = Catalog.create_res(%{kind: :place})

        {:ok, _name} =
          Catalog.create_nomen(%{
            res_id: place.id,
            nomen_string: name,
            provenance: :automatic,
            assigner_id: agent,
            language_unknown: true
          })

        {:ok, _identifier} =
          Catalog.create_nomen(%{
            res_id: place.id,
            nomen_string: Integer.to_string(geonameid),
            scheme: Registry.scheme!(@scheme),
            provenance: :automatic,
            assigner_id: agent
          })

        Repo.insert!(%PlaceKey{geonameid: geonameid, place_id: place.id})
        place.id
    end
  end

  defp within!(place, containing) do
    refinement = Refinements.name!("place-within-place")

    unless associated?(place, containing, refinement) do
      {:ok, _} = Catalog.associate(place, containing, refinement, :automatic)
    end
  end

  # The work's place of capture becomes the one recorded. An automatic one from an earlier
  # answer that names somewhere else is removed, and is what the conclusion says was
  # replaced; nothing a member asserted is touched, because a work carrying one is settled
  # before this is reached.
  defp capture!(work, recorded) do
    refinement = Refinements.name!("place-of-capture")
    keep = recorded && recorded["place_id"]

    earlier =
      Repo.all(
        from a in Association,
          where: a.subject_id == ^work and a.refinement == ^refinement,
          where: a.provenance == :automatic,
          select: a.object_id
      )

    replaced = Enum.reject(earlier, &(&1 == keep))

    Repo.delete_all(
      from a in Association,
        where: a.subject_id == ^work and a.refinement == ^refinement,
        where: a.provenance == :automatic and a.object_id in ^replaced
    )

    if keep && keep not in earlier do
      {:ok, _} = Catalog.associate(work, keep, refinement, :automatic)
    end

    replaced
  end

  defp settled?(work) do
    refinement = Refinements.name!("place-of-capture")

    Repo.exists?(
      from a in Association,
        where: a.subject_id == ^work and a.refinement == ^refinement and a.provenance == :local
    )
  end

  defp associated?(subject, object, refinement) do
    Repo.exists?(
      from a in Association,
        where: a.subject_id == ^subject and a.object_id == ^object and a.refinement == ^refinement
    )
  end

  # spec-05 §8.5: the pair, the proposal, the source and the evidence. A pair already
  # raised — or already decided — is met rather than raised again.
  defp raise!(work, candidate, record) do
    place = candidate["place_id"]
    [left, right] = Enum.sort([work, place])

    %Candidate{}
    |> Candidate.raised_changeset(%{
      left_id: left,
      right_id: right,
      detected_at: DateTime.utc_now(),
      proposed: :place_of_capture,
      source: @corpus,
      match_record_id: record.id
    })
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:left_id, :right_id])
  end
end
