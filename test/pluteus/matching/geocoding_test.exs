defmodule Pluteus.Matching.GeocodingTest do
  @moduledoc """
  A photograph's EXIF position becomes where it was taken, at the granularity the
  evidence supports, from the gazetteer the household holds (spec-05 §7, §9.7,
  criteria 1, 2, 14, 15, 20, 25, 31, 39).

  Photographs are placed by the real pipeline and run through the key, resolve and apply
  stages against a small gazetteer in the corpora's database.
  """

  use Pluteus.DataCase, async: true

  import Ecto.Query, only: [from: 2]
  import Pluteus.IngestFixtures

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Res
  alias Pluteus.Corpus
  alias Pluteus.Corpus.Repo, as: CorpusRepo
  alias Pluteus.Dedup
  alias Pluteus.Dedup.Candidate
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Place
  alias Pluteus.Matching.Geocoding
  alias Pluteus.Matching.MatchRecord
  alias Pluteus.Matching.PlaceKey
  alias Pluteus.Matching.SourceAgent
  alias Pluteus.Principals

  @t0 ~U[2026-11-07 12:00:00.000000Z]

  # 42° 57' 48.24" N, 85° 40' 5.16" W: some ten metres from Grand Rapids's point.
  @here [
    {0x0001, :ascii, "N"},
    {0x0002, :rational, [{42, 1}, {57, 1}, {4824, 100}]},
    {0x0003, :ascii, "W"},
    {0x0004, :rational, [{85, 1}, {40, 1}, {516, 100}]}
  ]

  defp located(accuracy_metres) do
    case accuracy_metres do
      nil -> located_jpeg(@here)
      metres -> located_jpeg(@here ++ [{0x001F, :rational, [{metres, 1}]}])
    end
  end

  defp gazetteer_place!(geonameid, name, {latitude, longitude}, admin1 \\ "MI") do
    CorpusRepo.query!(
      """
      INSERT INTO geonames.places
        (geonameid, name, latitude, longitude, feature_class, feature_code, country_code, admin1_code)
      VALUES ($1, $2, $3, $4, 'P', 'PPL', 'US', $5)
      """,
      [geonameid, name, latitude, longitude, admin1]
    )
  end

  setup do
    _system = Principals.system!()

    gazetteer_place!(4_994_358, "Grand Rapids", {42.96336, -85.66809})
    gazetteer_place!(5_014_681, "Walker", {42.99836, -85.76809})
    gazetteer_place!(5_015_688, "Wyoming", {42.91336, -85.70531})
    gazetteer_place!(4_986_207, "Kentwood", {42.86947, -85.64475})
    gazetteer_place!(4_995_201, "Grandville", {42.90975, -85.76309})

    CorpusRepo.query!(
      "INSERT INTO geonames.admin1 (code, name, geonameid) VALUES ('US.MI', 'Michigan', 5001836)"
    )

    CorpusRepo.query!(
      "INSERT INTO geonames.countries (iso, name, geonameid) VALUES ('US', 'United States', 6252001)"
    )

    snapshot =
      "geonames" |> Corpus.begin(~D[2026-11-06]) |> Corpus.verified(%{}) |> Corpus.imported()

    %{inbox: inbox!(), snapshot: snapshot}
  end

  defp photograph!(inbox, bytes) do
    drop!(inbox, Path.join(unique_prefix(), "photos/holiday/IMG_0001.jpg"), bytes)
    [id] = inbox |> acquire_settled!(@t0) |> acquired()
    Place.place_due(inbox)
    acquisition = Ingest.get_acquisition!(id)
    %{acquisition: acquisition, work: Catalog.work_of(acquisition.digital_item_id)}
  end

  defp run_stages! do
    Geocoding.key_due()
    Geocoding.resolve_due()
    Geocoding.apply_due()
  end

  defp current_record(work) do
    Repo.one!(from m in MatchRecord, where: m.res_id == ^work and is_nil(m.superseded_by_id))
  end

  defp captured_at(work) do
    Repo.all(
      from a in Association,
        where: a.subject_id == ^work and a.refinement == "place-of-capture",
        select: {a.object_id, a.provenance}
    )
  end

  defp place(geonameid), do: Repo.get!(PlaceKey, geonameid).place_id

  defp within(place) do
    Repo.all(
      from a in Association,
        where: a.subject_id == ^place and a.refinement == "place-within-place",
        select: a.object_id
    )
  end

  describe "39. A precise position records the locality it was taken in" do
    test "the work is captured at the nearest settlement, within its division and country", %{
      inbox: inbox
    } do
      %{work: work, acquisition: acquisition} = photograph!(inbox, located(5))

      run_stages!()

      assert captured_at(work) == [{place(4_994_358), :automatic}]
      assert within(place(4_994_358)) == [place(5_001_836)]
      assert within(place(5_001_836)) == [place(6_252_001)]

      # 1, 14: what was asked, from which asset, against which snapshot, and what came of it.
      record = current_record(work)
      assert record.state == :applied
      assert record.asset_id == acquisition.id
      assert %{"latitude" => _, "longitude" => _, "accuracy" => 5.0} = record.query
      assert record.basis == :resemblance
      assert record.snapshot_on == ~D[2026-11-06]
      assert record.rank == "corpus"

      assert %{"recorded" => %{"granularity" => "locality", "geonameid" => 4_994_358}} =
               record.conclusion
    end

    test "2, 15: a place's name and identifier are GeoNames's, and GeoNames is an agent", %{
      inbox: inbox
    } do
      photograph!(inbox, located(5))
      run_stages!()

      agent = Repo.get!(SourceAgent, "geonames").agent_id
      assert Repo.get!(Res, agent).kind == :collective_agent

      nomens = Repo.all(from n in Nomen, where: n.res_id == ^place(4_994_358))

      assert %{nomen_string: "Grand Rapids", assigner_id: ^agent, language_unknown: true} =
               Enum.find(nomens, &is_nil(&1.scheme))

      assert %{nomen_string: "4994358", assigner_id: ^agent} =
               Enum.find(nomens, &(&1.scheme == "geonames"))
    end

    test "a place is one res however many photographs were taken in it", %{inbox: inbox} do
      %{work: first} = photograph!(inbox, located(5))
      %{work: second} = photograph!(inbox, located(4))

      run_stages!()

      assert captured_at(first) == captured_at(second)
      assert Repo.aggregate(from(k in PlaceKey, where: k.geonameid == 4_994_358), :count) == 1
    end
  end

  describe "39. A position that supports less records less, and raises the finer place" do
    test "with no stated accuracy the division is recorded and the locality raised", %{
      inbox: inbox
    } do
      %{work: work} = photograph!(inbox, located(nil))

      run_stages!()

      assert captured_at(work) == [{place(5_001_836), :automatic}]

      record = current_record(work)
      assert record.state == :applied

      [left, right] = Enum.sort([work, place(4_994_358)])

      assert %Candidate{
               signal: :matching,
               proposed: :place_of_capture,
               source: "geonames",
               match_record_id: match_record_id,
               decision: nil
             } = Repo.get_by!(Candidate, left_id: left, right_id: right)

      assert match_record_id == record.id
    end

    test "20: accepting the finer place asserts it, and no later answer touches it", %{
      inbox: inbox
    } do
      %{work: work} = photograph!(inbox, located(nil))
      run_stages!()

      [left, right] = Enum.sort([work, place(4_994_358)])
      candidate = Repo.get_by!(Candidate, left_id: left, right_id: right)
      member = Principals.system!().id

      {:ok, _decided} =
        Pluteus.Actor.as(member, fn -> Dedup.decide(candidate.id, :place_of_capture, member) end)

      assert captured_at(work) == [{place(4_994_358), :local}]

      # A newer snapshot makes the match due again; the member's answer settles it, and the
      # decided candidate is not raised again.
      "geonames" |> Corpus.begin(~D[2026-12-06]) |> Corpus.verified(%{}) |> Corpus.imported()
      run_stages!()

      assert captured_at(work) == [{place(4_994_358), :local}]
      assert %{"settled" => _} = current_record(work).conclusion
      assert Repo.get!(Candidate, candidate.id).decision == :place_of_capture
    end

    test "a decision other than as proposed or distinct is refused", %{inbox: inbox} do
      %{work: work} = photograph!(inbox, located(nil))
      run_stages!()

      [left, right] = Enum.sort([work, place(4_994_358)])
      candidate = Repo.get_by!(Candidate, left_id: left, right_id: right)
      member = Principals.system!().id

      assert {:error, %Ecto.Changeset{}} =
               Pluteus.Actor.as(member, fn -> Dedup.decide(candidate.id, :same_work, member) end)
    end
  end

  describe "§11. A photograph with nothing to ask, or nothing near, says nothing" do
    test "one carrying no position is recorded empty and not read again", %{inbox: inbox} do
      %{work: work} = photograph!(inbox, media!(:jpeg))

      run_stages!()
      run_stages!()

      assert [%MatchRecord{state: :empty, query: query, response: nil}] =
               Repo.all(from m in MatchRecord, where: m.res_id == ^work)

      assert query == %{}
      assert captured_at(work) == []
    end

    test "25: one with no settlement near enough is empty, and not due again", %{inbox: inbox} do
      far = [
        {0x0001, :ascii, "N"},
        {0x0002, :rational, [{10, 1}, {0, 1}, {0, 1}]},
        {0x0003, :ascii, "W"},
        {0x0004, :rational, [{140, 1}, {0, 1}, {0, 1}]},
        {0x001F, :rational, [{5, 1}]}
      ]

      %{work: work} = photograph!(inbox, located_jpeg(far))

      run_stages!()
      run_stages!()

      assert %MatchRecord{state: :empty, response: %{"neighbours" => []}} = current_record(work)
      assert Repo.aggregate(from(m in MatchRecord, where: m.res_id == ^work), :count) == 1
      assert captured_at(work) == []
    end

    test "one whose position cannot be read is a finding, and out of due work", %{inbox: inbox} do
      unreferenced = [{0x0002, :rational, [{42, 1}, {57, 1}, {0, 1}]}, {0x0003, :ascii, "W"}]
      %{work: work, acquisition: acquisition} = photograph!(inbox, located_jpeg(unreferenced))

      run_stages!()
      run_stages!()

      assert [finding] =
               Ingest.findings_for_acquisition(acquisition.id)
               |> Enum.filter(&(&1.stage == :match))

      assert finding.kind == "position_unreadable"
      assert Repo.all(from m in MatchRecord, where: m.res_id == ^work) == []
    end
  end

  describe "§6.5, §8.7. A newer snapshot makes every answer due again" do
    test "its answer supersedes the earlier one, and both are kept", %{inbox: inbox} do
      %{work: work} = photograph!(inbox, located(5))
      run_stages!()
      earlier = current_record(work)

      "geonames" |> Corpus.begin(~D[2026-12-06]) |> Corpus.verified(%{}) |> Corpus.imported()
      run_stages!()

      later = current_record(work)
      assert later.id != earlier.id
      assert later.snapshot_on == ~D[2026-12-06]
      assert later.state == :applied
      assert Repo.get!(MatchRecord, earlier.id).superseded_by_id == later.id
      assert captured_at(work) == [{place(4_994_358), :automatic}]
    end

    test "an answer that changes replaces matching's own place of capture", %{inbox: inbox} do
      %{work: work} = photograph!(inbox, located(5))
      run_stages!()

      # The next snapshot moves the settlement's point twenty kilometres away, so the
      # coordinate now supports only the division.
      CorpusRepo.query!("UPDATE geonames.places SET latitude = 43.15 WHERE geonameid = 4994358")

      "geonames" |> Corpus.begin(~D[2026-12-06]) |> Corpus.verified(%{}) |> Corpus.imported()
      run_stages!()

      assert captured_at(work) == [{place(5_001_836), :automatic}]
      assert %{"replaced" => [replaced]} = current_record(work).conclusion
      assert replaced == place(4_994_358)
    end
  end

  describe "31. Nothing is asked of anyone outside the house" do
    test "with no snapshot imported, a keyed position waits rather than being sent anywhere",
         %{inbox: inbox, snapshot: snapshot} do
      Corpus.Repo.delete!(snapshot)
      %{work: work} = photograph!(inbox, located(5))

      run_stages!()

      assert current_record(work).state == :keyed
      assert captured_at(work) == []
    end
  end
end
