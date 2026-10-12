defmodule PluteusWeb.EntityLiveTest do
  @moduledoc """
  An entity's page as a person reaches it (spec-10 §8.4, §9.1, §10.1).

  Built on a placed album rather than on rows assembled for the test, because what the
  page renders is the representation of what ingest wrote: a holding with a credit, a
  date and a file reaches relations a holding built by hand does not, and those are the
  ones a page has to link to.
  """

  use PluteusWeb.ConnCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Res
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.MusicFixtures
  alias Pluteus.Repo
  alias PluteusWeb.Native

  setup %{conn: conn} do
    library = MusicFixtures.library!()

    %{
      conn: conn |> through_proxy(a_subject()) |> on_a_surface(),
      library: library,
      inbox: inbox!(),
      album: work_of(library.albums["01 So What.flac"])
    }
  end

  describe "§9.1, §10.1. A work answers with the interface where one is asked for" do
    test "an album renders, named and said to be what it is", %{conn: conn, album: album} do
      rendered = as_a_person(conn, ~p"/works/#{album}")

      assert rendered.status == 200
      assert html_response(rendered, 200) =~ "Kind of Blue"
    end

    test "the same address answers the representation where none is asked for",
         %{conn: conn, album: album} do
      answered = get(conn, ~p"/works/#{album}")

      assert json_response(answered, 200)["kind"] == "work"
    end
  end

  describe "§8.4. Every res the page relates to is linked at the address it has" do
    test "an album links to the artist it credits", %{conn: conn, album: album} do
      # The artist is a res of its own and the one kind a row may leave, being an agent
      # of an undetermined one of the two. A page that could not address it raised
      # rather than rendering, and every album credits one.
      body = conn |> as_a_person(~p"/works/#{album}") |> html_response(200)

      assert body =~ "/artists/"
    end

    test "it links to what realizes it", %{conn: conn, album: album} do
      # The failure this exists to prevent is not a missing link but a raise: the page
      # builds every related address at once, so one kind with no path takes the whole
      # page down rather than leaving one link out of it. A work relates to its
      # expressions; what embodies those is related to them and not to it.
      body = conn |> as_a_person(~p"/works/#{album}") |> html_response(200)

      assert body =~ "/expressions/"
    end
  end

  describe "§8.4. An agent's page is what it is credited on" do
    test "the band holds the release and not its tracks",
         %{conn: conn, album: album, library: library} do
      artist = credited_on(conn, album)

      body = conn |> as_a_person(~p"/artists/#{artist}") |> html_response(200)

      assert body =~ ~s|id="entity-credits"|
      assert body =~ ~s|href="/works/#{album}"|

      # Every track credits the artist too, and the release presents them, so the band
      # holds the release alone: three credits, one holding.
      assert body =~ "1 holding"
      assert match?([_one, _two | _more], tracks(library))
    end

    test "a release that holds a cover is drawn with it", %{conn: conn, album: album} do
      artist = credited_on(conn, album)

      body = conn |> as_a_person(~p"/artists/#{artist}") |> html_response(200)

      assert body =~ "/presentation/image-320"
    end

    test "a holding is not an agent, and carries no such band", %{conn: conn, album: album} do
      body = conn |> as_a_person(~p"/works/#{album}") |> html_response(200)

      refute body =~ ~s|id="entity-credits"|
    end
  end

  describe "§8.4. A work that gathers others lists what it gathers" do
    test "a series lists its episodes in the order its manifestation arranges them",
         %{conn: conn, inbox: inbox} do
      series = a_series(inbox, ["101 - Pilot.mkv", "102 - Square Peg.mkv"])

      body = conn |> as_a_person(~p"/works/#{series}") |> html_response(200)

      assert body =~ ~s|id="entity-members"|
      assert body =~ "Episodes"
      assert body =~ "2 episodes held, in arrangement order"
      assert body =~ "101 - Pilot"
      assert body =~ "102 - Square Peg"
    end

    # §5.2 makes *not held* a state of a res the catalog records, and the gap in a run of
    # episodes is the thing a person is looking for.
    test "an episode the catalog records and the household does not hold is drawn as not held",
         %{conn: conn, inbox: inbox} do
      series = a_series(inbox, ["101 - Pilot.mkv"])
      absent = recorded_not_held(series, 102, "Square Peg")

      body = conn |> as_a_person(~p"/works/#{series}") |> html_response(200)

      assert body =~ "1 episode held, in arrangement order"
      assert body =~ ~s|id="member-#{absent}"|
      assert body =~ "Not held"
      assert body =~ "Square Peg"
    end

    # §8.1 resolves the action over the thing itself, and a series is not a thing anybody
    # plays: what there is to do with it is to carry on with a member.
    test "a series' action reaches a member rather than being disabled",
         %{conn: conn, inbox: inbox} do
      series = a_series(inbox, ["101 - Pilot.mkv", "102 - Square Peg.mkv"])

      body = conn |> as_a_person(~p"/works/#{series}") |> html_response(200)

      assert body =~ "Start with 101 - Pilot"
      assert body =~ ~s|id="entity-primary-action"|
      refute body =~ ~s|id="entity-action-why"|
    end

    test "a holding that gathers nothing carries no such band", %{conn: conn, library: library} do
      track = work_of(library.songs["01 So What.flac"])

      body = conn |> as_a_person(~p"/works/#{track}") |> html_response(200)

      refute body =~ ~s|id="entity-members"|
    end

    test "a release lists the tracks it was released as", %{conn: conn, album: album} do
      body = conn |> as_a_person(~p"/works/#{album}") |> html_response(200)

      assert body =~ ~s|id="entity-members"|
      assert body =~ "Tracks"
    end
  end

  describe "§10.1. Every res the model admits has an address" do
    test "every kind that names a subtype is served under a path" do
      # The tripwire. A kind added to the model and not to the table is not a missing
      # link: every related address is built at once, so it is a page that raises.
      for kind <- Res.kinds() -- Native.addressless() do
        assert Map.has_key?(Native.paths(), kind),
               "a res of kind #{kind} can be held and cannot be addressed"
      end
    end

    test "the kinds §9.1 says answer with an interface are the ones that do" do
      # §9.1 names agents rather than the kinds an agent may be, and there are three.
      for kind <- ~w(person collective_agent artist)a do
        assert Native.negotiates?(kind), "#{kind} is an agent and answers no interface"
      end

      for kind <- ~w(nomen annotation asset)a do
        refute Native.negotiates?(kind), "#{kind} answers an interface §9.1 denies it"
      end
    end
  end

  describe "§9.1. A kind with no interface page stays reachable as the representation" do
    test "an asset answers JSON whatever was asked for", %{conn: conn, library: library} do
      # spec-03 §10 asks that an asset's location not be exposed on a reachable surface.
      [asset] = Catalog.assets_of(item_of(library.songs["01 So What.flac"]))

      answered = as_a_person(conn, ~p"/assets/#{asset.id}")

      assert json_response(answered, 200)["kind"] == "asset"
    end
  end

  # Episodes placed from the directory a household filed them under, which is what makes
  # the series: nothing in a rip states the show it belongs to.
  defp a_series(inbox, file_names) do
    prefix = unique_prefix()

    files =
      for name <- file_names,
          into: %{},
          do: {"#{prefix}/TV/Pinwheel/Season 01/#{name}", media!(:film)}

    [episode | _rest] = ingest!(inbox, files)

    [%{inspiration_id: series}] = Catalog.inspirations_of(work_of(manifestation_of(episode)))

    series
  end

  # What spec-05's matching will record and nothing yet does: a member of the series the
  # catalog knows about and the household holds no file for.
  defp recorded_not_held(series, position, name) do
    {:ok, %{manifestation: manifestation}} =
      Catalog.create_work(%{nomen_string: name, provenance: :automatic})

    {:ok, _part} =
      Catalog.add_manifestation_part(gathering(series), manifestation.id, position)

    manifestation.id
  end

  defp gathering(work_id) do
    [expression | _rest] = Catalog.expressions_of(work_id)
    [manifestation | _more] = Catalog.manifestations_of(expression.id)

    manifestation.id
  end

  defp manifestation_of(acquisition) do
    Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id
  end

  defp ingest!(inbox, files) do
    for {path, bytes} <- files, do: drop!(inbox, path, bytes)

    ids = inbox |> acquire_settled!() |> acquired()

    place_all!(inbox)
    Normalize.normalize_due()

    ids |> Enum.map(&Ingest.get_acquisition!/1) |> Enum.sort_by(& &1.inbox_path)
  end

  defp as_a_person(conn, path) do
    conn |> Plug.Conn.put_req_header("accept", "text/html") |> get(path)
  end

  defp work_of(manifestation_id) do
    [expression | _rest] = Catalog.expressions_in(manifestation_id)

    expression.work_id
  end

  # Read off the release's own page, which is where a person reaches an artist from:
  # whoever it links to under `/artists` is who it credits.
  defp credited_on(conn, work_id) do
    body = conn |> as_a_person(~p"/works/#{work_id}") |> html_response(200)

    [_whole, artist] = Regex.run(~r|/artists/([0-9a-f-]{36})|, body)

    artist
  end

  defp tracks(library), do: for({_name, held} <- library.songs, do: work_of(held))

  defp item_of(manifestation_id) do
    [item | _rest] = Catalog.digital_items_of(manifestation_id)

    item.id
  end
end
