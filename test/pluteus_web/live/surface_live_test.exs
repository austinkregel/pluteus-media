defmodule PluteusWeb.SurfaceLiveTest do
  @moduledoc """
  The surface a holding's category is presented on (spec-10 §12.1, §10.1, §11.2).

  What is asserted here is the boundary rather than the drawing: that a path beneath a
  res reaches the surface its category names and nothing else, that the four refusals
  are refusals, and that a player reserves a box before any byte of the medium arrives.
  """

  use PluteusWeb.ConnCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Credit
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Place
  alias Pluteus.Lifecycle
  alias Pluteus.Paging
  alias Pluteus.Presentation.Generate
  alias Pluteus.Presentation.Geometry
  alias Pluteus.Presentation.Registry
  alias Pluteus.Principals
  alias Pluteus.Reading
  alias Pluteus.Repo
  alias Pluteus.Storage
  alias Pluteus.Surfaces.Registry, as: Surfaces
  alias PluteusWeb.Surfaces.Listening, as: Listen

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup %{conn: conn} do
    _system = Principals.system!()

    %{conn: conn |> through_proxy(a_subject()) |> on_a_surface(), inbox: inbox!()}
  end

  describe "§12.1, §10.1. A category is presented beneath the address its res has" do
    test "a holding played reaches the player", %{conn: conn} do
      film = named("Duck and Cover", "home_video")

      {:ok, _live, html} = live(conn, ~p"/works/#{film}/play")

      assert html =~ "Duck and Cover"
      assert html =~ ~s|id="player-picture"| or html =~ ~s|id="player-refusal"|
    end

    test "a holding read reaches the reader", %{conn: conn} do
      letter = named("A letter", "document")

      {:ok, _live, html} = live(conn, ~p"/works/#{letter}/read")

      assert html =~ "A letter"
    end

    # Every segment the router carries comes from the registry, so a category named
    # there and addressed nowhere would be a route to nothing.
    test "every segment the router builds is one a category is presented at" do
      addressed = Surfaces.surfaces()

      for category <- Surfaces.presented_categories(),
          surface = Surfaces.surface_of(category),
          surface != nil do
        assert surface in addressed,
               "#{category} is presented at #{surface}, which the router does not build"
      end

      assert addressed == ["play", "read", "view"]
    end
  end

  describe "§10.1. A path beneath a res refuses what it does not name" do
    test "an identifier that is not one is not found", %{conn: conn} do
      assert_raise PluteusWeb.NotFoundError, ~r/is not an identifier/, fn ->
        live(conn, ~p"/works/not-a-uuid/play")
      end
    end

    test "a work nobody holds is not found", %{conn: conn} do
      assert_raise PluteusWeb.NotFoundError, ~r/no holding is held/, fn ->
        live(conn, ~p"/works/#{Ecto.UUID.generate()}/play")
      end
    end

    test "a surface the category is not presented on is not found", %{conn: conn} do
      film = named("Duck and Cover", "home_video")

      assert_raise PluteusWeb.NotFoundError, ~r/not presented/, fn ->
        live(conn, ~p"/works/#{film}/read")
      end
    end

    # The identifier stays refused rather than becoming someone else's, so this is not
    # the same answer as a work nobody holds.
    test "a recycled holding is gone, not absent", %{conn: conn} do
      film = named("Duck and Cover", "home_video")
      {:ok, principal} = Principals.create_principal(%{role: "member"})
      {:ok, _recycling} = Lifecycle.recycle(film, principal.id)

      assert_raise PluteusWeb.GoneError, ~r/recycle bin/, fn ->
        live(conn, ~p"/works/#{film}/play")
      end
    end
  end

  describe "§11.2. A player reserves its box before the medium arrives" do
    # A page that reflows as its medium loads moves what a person was reaching for. The
    # holding here has no bytes at all, so what is reserved is §20's own figure for the
    # category and not a measurement.
    test "a holding nothing has probed still reserves the category's ratio",
         %{conn: conn} do
      film = named("Duck and Cover", "home_video")

      {:ok, _live, html} = live(conn, ~p"/works/#{film}/play")

      assert html =~ "aspect-ratio: 1.7778"
    end

    test "a holding with no file says so inside the box it reserved", %{conn: conn} do
      film = named("Duck and Cover", "home_video")

      {:ok, _live, html} = live(conn, ~p"/works/#{film}/play")

      assert html =~ ~s|id="player-refusal"|
      assert html =~ "No file is held for this."
    end
  end

  describe "§12.2. The medium's own tracks, each choice its own state" do
    test "the audio tracks a file carries are listed, by what the file states",
         %{conn: conn, inbox: inbox} do
      # Two audio tracks, one Russian and one English, which is what the fixture's
      # container declares. What a person may choose between is a property of the
      # bytes rather than of the work, so it is read from them.
      film = a_film(inbox)

      {:ok, live, _html} = live(conn, ~p"/works/#{film}/play")

      assert has_element?(live, "#player-audio", "rus")
      assert has_element?(live, "#player-audio", "eng")
      assert has_element?(live, "#player-audio", "flac")
      assert has_element?(live, "#player-audio", "aac")
    end

    test "a medium carrying no subtitles says so rather than offering none",
         %{conn: conn, inbox: inbox} do
      film = a_film(inbox)

      {:ok, _live, html} = live(conn, ~p"/works/#{film}/play")

      assert html =~ "None held."
    end

    test "the picture is a video element pointed at the bytes",
         %{conn: conn, inbox: inbox} do
      film = a_film(inbox)

      {:ok, _live, html} = live(conn, ~p"/works/#{film}/play")

      assert html =~ ~s|id="player-medium"|
      assert html =~ "<video"
      assert html =~ "/content"
    end

    # The medium carries no controls of its own: §12.3's are below it, and two sets
    # over one medium leaves a person pressing whichever they reached first.
    test "the medium carries no second set of controls", %{conn: conn, inbox: inbox} do
      film = a_film(inbox)

      {:ok, _live, html} = live(conn, ~p"/works/#{film}/play")

      refute html =~ ~s|<video id="player-medium" controls|
      assert html =~ ~s|phx-hook="Player"|
    end

    # §11.3's frames, which a person scrubbing is shown. The surface carries the figures
    # that find a frame in the sprite rather than the frame: which one to show follows
    # from a position the server does not have.
    test "the frames are offered where they are held, and asked for where they are not",
         %{conn: conn, inbox: inbox} do
      # Longer than one interval, because §20 puts a frame every ten seconds and a
      # holding shorter than that has no frame to put anywhere.
      film = a_moving_picture(inbox)
      manifestation = manifestation_of(film)

      {:ok, _live, asked} = live(conn, ~p"/works/#{film}/play")

      # Nothing has made them yet, so the first visit shows none and asks.
      refute asked =~ ~s|id="player-trickplay"|

      {:ok, made} = Generate.run(manifestation, Registry.trickplay()["name"])
      on_exit(fn -> Storage.delete(made.location) end)

      {:ok, _live, held} = live(conn, ~p"/works/#{film}/play")

      assert held =~ ~s|id="player-trickplay"|
      assert held =~ ~s|data-interval="10000"|
      assert held =~ ~s|data-frame-width="320"|
    end

    # The canvas's own note on this board: a pill reading "Direct play — no transcode"
    # asserts an outcome nothing has established. What this deployment can state is what
    # it handed over, which is the stored bytes under the media type it served them as.
    test "the surface states what it served, not what will happen",
         %{conn: conn, inbox: inbox} do
      film = a_film(inbox)

      {:ok, _live, html} = live(conn, ~p"/works/#{film}/play")

      assert html =~ ~s|id="player-delivery"|
      assert html =~ "Served as held"
      assert html =~ "Matroska"
    end

    # Whether the bytes play is the browser's answer, so it is the browser that reports
    # it and the surface that words it: §8.5 keeps a media error code off a surface.
    test "a browser that will not play it says so on the surface",
         %{conn: conn, inbox: inbox} do
      film = a_film(inbox)

      {:ok, live, html} = live(conn, ~p"/works/#{film}/play")

      refute html =~ ~s|id="player-stopped"|

      render_hook(live, "medium-refused", %{"code" => 4, "said" => "unsupported codec"})

      assert render(live) =~ "This browser does not play what this is held as."
      assert render(live) =~ "unsupported codec"
    end

    # §12.2 and spec-01 §8.6 keep three things apart: which audio plays, which subtitle
    # track is chosen, and whether subtitles are shown at all. The third outlives the
    # holding, so it is the principal's and not this page's.
    test "whether subtitles are shown is a third state, and it is kept",
         %{conn: conn, inbox: inbox} do
      film = a_film(inbox)

      {:ok, live, html} = live(conn, ~p"/works/#{film}/play")

      assert html =~ ~s|id="player-shown"|
      assert has_element?(live, ~s|[phx-value-key="subtitle_visibility"][aria-pressed="true"]|)

      live
      |> element(~s|button[phx-value-key="subtitle_visibility"]|, "Foreign audio")
      |> render_click()

      assert has_element?(
               live,
               ~s|button[phx-value-value="foreign_audio"][aria-pressed="true"]|
             )

      # Choosing it says nothing about which track is chosen, which §12.2 forbids
      # collapsing into one setting.
      refute has_element?(live, ~s|#player-subtitles [aria-pressed="true"]|)
    end

    # §17.4 requires a caption's presentation be adjustable and persisted per principal,
    # and names no property of it; these four are what this deployment draws and §20 is
    # where their values live.
    test "a caption is drawn as this principal asked", %{conn: conn, inbox: inbox} do
      film = a_film(inbox)

      {:ok, live, html} = live(conn, ~p"/works/#{film}/play")

      assert html =~ ~s|id="player-captions"|

      for key <- PluteusWeb.Settings.keys(:captions) do
        assert has_element?(live, ~s|[phx-value-key="#{key}"]|) or
                 has_element?(live, ~s|#preference-#{key}|),
               "#{key} is a caption setting and nothing offers it"
      end
    end

    test "choosing a track holds the choice, and holds the other apart from it",
         %{conn: conn, inbox: inbox} do
      film = a_film(inbox)

      {:ok, live, _html} = live(conn, ~p"/works/#{film}/play")

      refute has_element?(live, ~s|#player-audio [aria-pressed="true"]|)

      live
      |> element(~s|#player-audio button[phx-value-index="2"]|)
      |> render_click()

      assert has_element?(
               live,
               ~s|#player-audio button[phx-value-index="2"][aria-pressed="true"]|
             )

      # §12.2 keeps the two apart: choosing audio says nothing about subtitles.
      refute has_element?(live, ~s|#player-subtitles [aria-pressed="true"]|)
    end
  end

  describe "§12.1, §11.2. A photograph is looked at, and its box is reserved" do
    test "the viewer asks for the picture at the manifestation's own address",
         %{conn: conn} do
      photo = named("A photograph", "photograph")

      {:ok, _live, html} = live(conn, ~p"/works/#{photo}/view")

      refute html =~ ~s|id="player-medium"|
      assert html =~ ~s|id="viewer-image"|
      assert html =~ "/presentation/image-2048"
      assert html =~ "/presentation/image-160 160w"
    end

    # §20's assumed ratio for the category, since nothing has probed these bytes. A box
    # that collapsed to nothing and grew would move what a person was reaching for.
    test "a holding nothing has probed still reserves the category's ratio",
         %{conn: conn} do
      photo = named("A photograph", "photograph")

      {:ok, _live, html} = live(conn, ~p"/works/#{photo}/view")

      assert html =~ "aspect-ratio: 1.5"
    end

    # A still image is a container with no duration — ffprobe's format block has no such
    # field for a JPEG — and a photograph is not zero milliseconds long. The surface
    # asks what is playable before it knows the category, so a reading with no length
    # has to be an answer rather than a raise.
    test "a photograph whose bytes were read has no length, and still renders",
         %{conn: conn, inbox: inbox} do
      photo = a_photograph(inbox)

      {:ok, _live, html} = live(conn, ~p"/works/#{photo}/view")

      assert html =~ ~s|id="viewer-image"|
    end

    test "a photograph is not offered a transport", %{conn: conn} do
      photo = named("A photograph", "photograph")

      {:ok, _live, html} = live(conn, ~p"/works/#{photo}/view")

      refute html =~ ~s|id="player-transport"|
      assert html =~ ~s|id="transport-live"|
    end
  end

  describe "§12.1, §11.5. A publication is read a division at a time" do
    test "the text is shown divided as the publication divides it",
         %{conn: conn, inbox: inbox} do
      book = a_book(inbox)

      {:ok, live, html} = live(conn, ~p"/works/#{book}/read")

      assert html =~ "Dear Ada and Thomas"
      refute html =~ "Write when you can"
      assert html =~ "Page 1 of 2"

      live |> element(~s|#reader-position button[phx-value-to="1"]|) |> render_click()

      assert render(live) =~ "Write when you can"
      assert has_element?(live, "#reader-position", "Page 2 of 2")
    end

    # A position past the end is the end. A person pressing the last page twice, or a
    # slider arriving at a figure from a copy with more pages in it, has not asked for
    # a page the publication does not have.
    test "a position outside the publication is clamped to it", %{conn: conn, inbox: inbox} do
      book = a_book(inbox)

      {:ok, live, _html} = live(conn, ~p"/works/#{book}/read")

      live |> element("#reader-at") |> render_change(%{"to" => "40"})

      assert has_element?(live, "#reader-position", "Page 2 of 2")
    end

    test "the copy being read is named, and so is every other copy",
         %{conn: conn, inbox: inbox} do
      book = a_book(inbox)

      {:ok, _live, html} = live(conn, ~p"/works/#{book}/read")

      assert html =~ "Held as"
      assert html =~ "PDF"
    end

    # The copy is named by a parameter of the surface rather than by an address of its
    # own, so one the household does not hold is the same answer as a work it does not
    # hold: not found.
    test "a copy nobody holds is not found", %{conn: conn, inbox: inbox} do
      book = a_book(inbox)

      assert_raise PluteusWeb.NotFoundError, ~r/no copy of this is held/, fn ->
        live(conn, ~p"/works/#{book}/read?held=#{Ecto.UUID.generate()}")
      end
    end

    # §11.6 answers an artefact nobody has made and one there is nothing to make alike,
    # and §5.2 is where they differ. A holding with no bytes is the second.
    test "a holding with no bytes states the absence of its text in words",
         %{conn: conn} do
      letter = named("A letter", "document")

      {:ok, _live, html} = live(conn, ~p"/works/#{letter}/read")

      assert html =~ ~s|id="reader-absence"|
      assert html =~ "No text is held for this."
      refute html =~ ~s|id="reader-position"|
    end
  end

  describe "§12.1. A reading is presented with the chapters its container states" do
    test "the chapters are listed in reading order, as the container named them",
         %{conn: conn, inbox: inbox} do
      book =
        a_reading(inbox,
          chapters: [{"The Shadow", {0, 3_000}}, {"The Loosing", {3_000, 6_000}}]
        )

      {:ok, live, html} = live(conn, ~p"/works/#{book}/play")

      assert html =~ "2 chapters"
      assert has_element?(live, ~s|#listening-chapters button[phx-value-index="0"]|, "The Shadow")

      assert has_element?(
               live,
               ~s|#listening-chapters button[phx-value-index="1"]|,
               "The Loosing"
             )
    end

    # Placement records what the container declared and nothing else, so a reading that
    # declares none has none — and the parts a reading in several files is carried by are
    # where the bytes are, not divisions anybody made.
    test "a reading whose container states no chapters says so", %{conn: conn, inbox: inbox} do
      book = a_reading(inbox, chapters: nil)

      {:ok, _live, html} = live(conn, ~p"/works/#{book}/play")

      assert html =~ ~s|id="listening-chapters-absent"|
      assert html =~ "Nothing in this states where its chapters are."
      refute html =~ ~s|id="listening-chapters"|
    end

    # Pressing a chapter is asking to be taken there, which the player does by being told
    # where to be rather than by a report of having reached it: §13.2's thresholds would
    # discard a position at the beginning of the first chapter.
    test "pressing a chapter starts the reading and takes the player there",
         %{conn: conn, inbox: inbox} do
      book =
        a_reading(inbox,
          chapters: [{"The Shadow", {0, 3_000}}, {"The Loosing", {3_000, 6_000}}]
        )

      {:ok, live, _html} = live(conn, ~p"/works/#{book}/play")

      live |> element(~s|#listening-chapters button[phx-value-index="1"]|) |> render_click()

      assert live |> find_live_child("transport-live") |> render() =~ ~s|data-position="3000"|
    end

    test "who the reading credits is said in the role each is credited in",
         %{conn: conn, inbox: inbox} do
      book = a_reading(inbox, chapters: nil)

      {:ok, _live, html} = live(conn, ~p"/works/#{book}/play")

      assert html =~ "Written by Ursula K. Le Guin"
      assert html =~ "Read by Rob Inglis"
    end

    # §8.5 keeps the model's own vocabulary off a surface, and a role with no words for it
    # would reach a person as the column's value.
    test "every role a credit may be in is said in words" do
      for role <- Credit.roles() do
        assert is_binary(Listen.in_role(role)), "#{role} is a credit role nothing says"
      end
    end
  end

  describe "§12.1, §12.3. A container of pages is read one page at a time" do
    test "the position runs over the pages placement counted, not the pages made",
         %{conn: conn, inbox: inbox} do
      comic = a_comic(inbox, 3)

      {:ok, live, html} = live(conn, ~p"/works/#{comic}/read")

      assert html =~ "Page 1 of 3"
      assert has_element?(live, "#page-position")
    end

    test "turning the page moves the position", %{conn: conn, inbox: inbox} do
      comic = a_comic(inbox, 3)

      {:ok, live, _html} = live(conn, ~p"/works/#{comic}/read")

      live |> element(~s|#page-position button[phx-value-to="1"]|) |> render_click()

      assert has_element?(live, "#page-position", "Page 2 of 3")
    end

    # A page past the end is the end, as a position past the end of a publication is.
    test "a page outside the issue is clamped to it", %{conn: conn, inbox: inbox} do
      comic = a_comic(inbox, 3)

      {:ok, live, _html} = live(conn, ~p"/works/#{comic}/read")

      live |> element("#page-at") |> render_change(%{"to" => "40"})

      assert has_element?(live, "#page-position", "Page 3 of 3")
    end

    # Nothing counted the pages, so §12.3 has nowhere to put a position: the slider would
    # run over a figure this deployment made up.
    test "a holding whose pages nothing counted has no page to turn to", %{conn: conn} do
      issue = named("An issue", "comic_issue")

      {:ok, _live, html} = live(conn, ~p"/works/#{issue}/read")

      assert html =~ ~s|id="page-absence"|
      assert html =~ "Nothing has counted the pages of this"
      refute html =~ ~s|id="page-position"|
    end
  end

  describe "§11.2, §11.6. A page absent is a state, inside the box kept for it" do
    test "a page nothing has made yet says so, and the box is the category's ratio",
         %{conn: conn, inbox: inbox} do
      comic = a_comic(inbox, 2)

      {:ok, _live, html} = live(conn, ~p"/works/#{comic}/read")

      assert html =~ ~s|id="page-absent"|
      assert html =~ "This page is being made."
      assert html =~ "aspect-ratio: 0.6471"
      assert html =~ "Page 1 of 2"
    end

    # The widths of one page are not the shape of the holding: an archive has no one
    # shape, so what reserves the box is what the page itself was measured at.
    test "a page that has been made is shown at its own shape, at every width held",
         %{conn: conn, inbox: inbox} do
      comic = a_comic(inbox, 2)
      subject = manifestation_of(comic)

      {:ok, made} = Generate.run(subject, "image-160", 0)
      on_exit(fn -> Storage.delete(made.location) end)

      {:ok, _live, html} = live(conn, ~p"/works/#{comic}/read")

      assert html =~ ~s|id="page-image"|
      assert html =~ "presentation/image-160/0 #{made.width}w"
      assert html =~ "aspect-ratio: #{Geometry.ratio(made.width, made.height)}"
      refute html =~ "aspect-ratio: 0.6471"
    end

    # The page arrives on its own: the surface asked for it, looked again and drew it,
    # because an image element has no way to ask a second time for itself.
    test "a page made while the surface is open is drawn when it arrives",
         %{conn: conn, inbox: inbox} do
      comic = a_comic(inbox, 2)

      {:ok, live, html} = live(conn, ~p"/works/#{comic}/read")

      assert html =~ "This page is being made."

      {:ok, made} = Generate.run(manifestation_of(comic), "image-160", 0)
      on_exit(fn -> Storage.delete(made.location) end)

      send(live.pid, :page_again)

      assert render(live) =~ ~s|id="page-image"|
    end

    # A page offered at a width that is not there would draw nothing where a browser
    # chose it, so the set a browser chooses from is the set that is held.
    test "a width nothing has made is not offered", %{conn: conn, inbox: inbox} do
      comic = a_comic(inbox, 2)

      {:ok, made} = Generate.run(manifestation_of(comic), "image-160", 0)
      on_exit(fn -> Storage.delete(made.location) end)

      {:ok, _live, html} = live(conn, ~p"/works/#{comic}/read")

      refute html =~ "presentation/image-2048/0"
    end

    # §5.2 distinguishes a page nobody has made from one a tool tried and could not, and
    # the second is not asked for again: the same entry at the same version answers the
    # same way, and the finding is what a person clears to say try once more.
    test "a page a tool could not read says so, and is not asked for again",
         %{conn: conn, inbox: inbox} do
      comic =
        a_comic(inbox, [
          {"page-1.png", comic_page(1)},
          {"page-2.png", "this is not a picture"}
        ])

      subject = manifestation_of(comic)

      assert {:error, "derivative_not_generated", _detail} = Generate.run(subject, "image-160", 1)

      {:ok, live, _html} = live(conn, ~p"/works/#{comic}/read")

      live |> element(~s|#page-position button[phx-value-to="1"]|) |> render_click()
      html = render(live)

      assert html =~ "This page could not be read from the file."
      assert html =~ "Page 2 of 2"
      assert Paging.ask(subject, 1) == :attempted_failed
    end
  end

  describe "A.3.6, §14.5. How a person is read to is theirs alone" do
    test "a setting pressed is kept, and nobody else is set by it",
         %{conn: conn, inbox: inbox} do
      book = a_book(inbox)

      {:ok, live, html} = live(conn, ~p"/works/#{book}/read")

      assert html =~ "font-family: var(--font-serif);"

      live
      |> element(~s|#reading-preferences button[phx-value-key="reading_face"]|, "Sans")
      |> render_click()

      assert render(live) =~ "font-family: var(--font-sans);"

      # A second member on the same holding is read to as they asked, which is what
      # §14.5 means by a preference not being visible to another.
      another = build_conn() |> through_proxy(a_subject("marie")) |> on_a_surface()

      {:ok, _live, theirs} = live(another, ~p"/works/#{book}/read")

      assert theirs =~ "font-family: var(--font-serif);"
    end

    test "every property the registry carries is offered", %{conn: conn, inbox: inbox} do
      book = a_book(inbox)

      {:ok, live, _html} = live(conn, ~p"/works/#{book}/read")

      for key <- PluteusWeb.Surfaces.Reading.keys() do
        assert has_element?(live, ~s|#reading-preferences [phx-value-key="#{key}"]|) or
                 has_element?(live, ~s|#preference-#{key}|),
               "#{key} is a reading preference and nothing offers it"
      end
    end
  end

  describe "A surface that takes the width gives it back when asked" do
    test "the rail opens collapsed on a player and reopens on a press",
         %{conn: conn, inbox: inbox} do
      film = a_film(inbox)

      {:ok, live, _html} = live(conn, ~p"/works/#{film}/play")

      assert has_element?(live, ~s|button[phx-click="rail-toggle"][aria-expanded="false"]|)

      live |> element(~s|button[phx-click="rail-toggle"]|) |> render_click()

      assert has_element?(live, ~s|button[phx-click="rail-toggle"][aria-expanded="true"]|)
    end

    # The queue's player and the surface's medium would otherwise run at once.
    test "a surface holding its own medium carries no queue player",
         %{conn: conn, inbox: inbox} do
      film = a_film(inbox)

      {:ok, _live, html} = live(conn, ~p"/works/#{film}/play")

      refute html =~ ~s|id="transport-live"|
    end

    # Music is the other way about: the surface starts the queue and the chrome's
    # transport carries it, which is what lets audio outlive moving to another surface.
    test "a surface that starts the queue carries the player that outlives it",
         %{conn: conn} do
      song = named("A song", "music_recording")

      {:ok, _live, html} = live(conn, ~p"/works/#{song}/play")

      assert html =~ ~s|id="transport-live"|
    end
  end

  # Placed and normalized, so there is a master to play from: the surface reads the
  # tracks off the bytes, and bytes nothing has normalized are refused before it looks.
  defp a_film(inbox) do
    drop!(inbox, "home video/#{unique_prefix()}/duck.mkv", media!(:film))

    [id] = inbox |> acquire_settled!(@t0) |> acquired()
    Place.place_due(inbox)
    Normalize.normalize_due(fn _class -> nil end)

    id |> Ingest.get_acquisition!() |> Map.fetch!(:digital_item_id) |> Catalog.work_of()
  end

  # Placed, probed and normalized, so the surface meets a holding whose reading states no
  # duration. Normalized because playback refuses bytes nothing has adopted a master for
  # before it ever asks how long they are, which is what made an earlier version of this
  # test pass against the defect it was written for.
  defp a_photograph(inbox) do
    drop!(inbox, "photos/#{unique_prefix()}/IMG_0001.png", media!(:png))

    [id] = inbox |> acquire_settled!(@t0) |> acquired()
    place_all!(inbox)
    Normalize.normalize_due(fn _class -> nil end)

    id |> Ingest.get_acquisition!() |> Map.fetch!(:digital_item_id) |> Catalog.work_of()
  end

  # Two pages of a publication, which is what makes a division a division: the text is
  # read out of the file and the form feed between the pages is the file's own.
  defp a_book(inbox) do
    drop!(inbox, "#{unique_prefix()}/letters.pdf", two_pages())

    [id] = inbox |> acquire_settled!(@t0) |> acquired()
    place_all!(inbox)
    Normalize.normalize_due(fn _class -> nil end)

    acquisition = Ingest.get_acquisition!(id)
    manifestation = Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id
    {:ok, made} = Generate.run(manifestation, Reading.profile())
    on_exit(fn -> Storage.delete(made.location) end)

    Catalog.work_of(acquisition.digital_item_id)
  end

  defp two_pages do
    """
    %PDF-1.4
    1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
    2 0 obj<</Type/Pages/Kids[3 0 R 6 0 R]/Count 2>>endobj
    3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 100]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj
    4 0 obj<</Length 60>>stream
    BT /F1 12 Tf 20 50 Td (Dear Ada and Thomas) Tj ET
    endstream
    endobj
    5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
    6 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 100]/Contents 7 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj
    7 0 obj<</Length 60>>stream
    BT /F1 12 Tf 20 50 Td (Write when you can) Tj ET
    endstream
    endobj
    trailer<</Root 1 0 R>>
    %%EOF
    """
  end

  defp a_moving_picture(inbox) do
    drop!(inbox, "home video/#{unique_prefix()}/birthday.mkv", media!(:ffv1, duration: 11))

    [id] = inbox |> acquire_settled!(@t0) |> acquired()
    place_all!(inbox)
    Normalize.normalize_due(fn _class -> nil end)

    id |> Ingest.get_acquisition!() |> Map.fetch!(:digital_item_id) |> Catalog.work_of()
  end

  # A reading placed and normalized, named and credited the way a published one arrives:
  # the author in `artist`, the narrator in `narratedby`, and the chapters the container
  # declares.
  defp a_reading(inbox, opts) do
    drop!(
      inbox,
      "#{unique_prefix()}/earthsea.m4b",
      # The narrator in `composer`, which is where an MP4 tagger writes one: the muxer
      # carries no field called after the act, and the registry names it among the tags a
      # narrator arrives in.
      reading(
        chapters: opts[:chapters],
        tags: %{"artist" => "Ursula K. Le Guin", "composer" => "Rob Inglis"}
      )
    )

    [id] = inbox |> acquire_settled!(@t0) |> acquired()
    place_all!(inbox)
    Normalize.normalize_due(fn _class -> nil end)

    id |> Ingest.get_acquisition!() |> Map.fetch!(:digital_item_id) |> Catalog.work_of()
  end

  # A comic archive placed and normalized, so the page reader meets a holding whose pages
  # placement counted from the archive's own entries and whose master a page can be
  # extracted from. Entries may be given outright, so a caller can put something in the
  # archive that an encoder cannot read.
  defp a_comic(inbox, pages) when is_integer(pages) do
    a_comic(inbox, for(n <- 1..pages, do: {"page-#{n}.png", comic_page(n)}))
  end

  defp a_comic(inbox, entries) when is_list(entries) do
    drop!(inbox, "#{unique_prefix()}/Excitebike Weekly 001.cbz", cbz(entries))

    [id] = inbox |> acquire_settled!(@t0) |> acquired()
    place_all!(inbox)
    Normalize.normalize_due(fn _class -> nil end)

    id |> Ingest.get_acquisition!() |> Map.fetch!(:digital_item_id) |> Catalog.work_of()
  end

  defp manifestation_of(work_id) do
    [expression | _rest] = Catalog.expressions_of(work_id)
    [manifestation | _more] = Catalog.manifestations_of(expression.id)

    manifestation.id
  end

  defp named(name, category) do
    {:ok, %{work: work}} = Catalog.create_work(%{nomen_string: name, provenance: :automatic})
    {:ok, _} = Catalog.categorize(work.id, Place.category_scheme(), category, :automatic)

    work.id
  end
end
