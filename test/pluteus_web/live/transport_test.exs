defmodule PluteusWeb.TransportTest do
  @moduledoc """
  The persistent transport as a person meets it (spec-10 §12.3, §12.4, criterion 40).

  What the bar shows comes from the queue, which is the principal's own, so these drive
  it the way a person does — press play on a row, then read what the chrome says — rather
  than asserting against a state assembled for the test.
  """

  use PluteusWeb.ConnCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Grouping
  alias Pluteus.Consumption
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Preferences
  alias Pluteus.Principals
  alias Pluteus.Repo

  setup %{conn: conn} do
    subject = a_subject()

    %{conn: conn |> through_proxy(subject) |> on_a_surface(), subject: subject}
  end

  describe "A.9.3, §5.3. The bar names itself and says what it is playing" do
    test "the controls are a toolbar, which is what carries the name", %{conn: conn} do
      # An aria-label on an element whose role is generic reaches nothing, so the name
      # has to sit on something that has a role.
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      assert has_element?(
               player(live),
               ~s|#transport-controls[role="toolbar"][aria-label="Transport"]|
             )
    end

    test "the kind is said in words and not only by a glyph and a hue", %{conn: conn} do
      # §5.3 and A.2.6 each forbid a hidden glyph or a hue being the sole carrier.
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      assert live |> player() |> element("#transport") |> render() =~ "Recordings"
    end
  end

  describe "A row and the bar say who a holding is by" do
    test "the artist leads the second line, and the kind follows it", %{conn: conn} do
      # The kind stays: it is what tells two holdings of one name apart.
      %{release: release} = a_credited_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")

      assert render(live) =~ "Miles Davis · Music"

      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      assert live |> player() |> element("#transport") |> render() =~ "Miles Davis · "
    end

    test "a holding crediting nobody says what it is and no more", %{conn: conn} do
      a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")

      assert render(live) =~ "Music · 2 tracks"
    end
  end

  describe "§13.1. Reporting a position advances the queue and moves nothing" do
    test "the queue carries where it reached, so a reload starts there",
         %{conn: conn, subject: subject} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      reported(live, 1_500)

      principal = Principals.principal_for(issuer(), subject)

      assert Consumption.play_queue(principal.id).position_ms == 1_500
    end

    test "a report changes nothing the element is told", %{conn: conn} do
      # The seek itself is the client's and no test here reaches it. This holds the
      # server's half: a report gives the element nothing new to follow.
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      before = live |> player() |> element("#transport-medium") |> render()
      reported(live, 1_500)

      assert live |> player() |> element("#transport-medium") |> render() == before,
             "a position report changed what the element is told, so it would seek"
    end
  end

  describe "Narrowing keeps what is playing" do
    test "a facet is a patch, so the page is not loaded again", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      before = live |> player() |> element("#transport-medium") |> render()

      render_patch(live, ~p"/everything?category=album,music_recording")

      assert live |> player() |> element("#transport-medium") |> render() == before,
             "narrowing changed what the element is told, so it would reload"

      assert has_element?(player(live), ~s|#transport-medium|)
    end

    test "every link that narrows carries a patch rather than a load", %{conn: conn} do
      # A load drops the socket, and with it the element that is playing.
      a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything")

      for narrowing <- ~w(category) do
        assert has_element?(
                 live,
                 ~s|a[data-phx-link="patch"][href*="#{narrowing}="]|
               ),
               "the #{narrowing} facet loads the page rather than patching it"
      end
    end

    test "a chip removing a narrowing patches too", %{conn: conn} do
      a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")

      assert has_element?(live, ~s|a[data-phx-link="patch"][aria-label^="Remove the facet"]|)
    end

    test "a row still loads the page, because one URI answers two representations",
         %{conn: conn} do
      a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")

      refute has_element?(live, ~s|a[data-phx-link][href^="/works/"]|)
    end
  end

  describe "§12.3. Nothing current means no transport" do
    test "the bar is absent before anything is played", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/everything")

      refute has_element?(player(live), "#transport")
    end
  end

  describe "§12.3. Every control states the action it will perform" do
    test "playing a holding draws the bar, named, with a pause control", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")

      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      assert has_element?(player(live), "#transport")
      assert has_element?(player(live), ~s|button[aria-label="Pause"]|)
      refute has_element?(player(live), ~s|button[aria-label="Play"][phx-click="transport-play"]|)
    end

    test "pausing it offers to play again", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")

      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()
      live |> player() |> element(~s|button[aria-label="Pause"]|) |> render_click()

      assert has_element?(player(live), ~s|button[aria-label="Play"][phx-click="transport-play"]|)
    end
  end

  describe "§12.3. The position slider carries both granularities and a spoken value" do
    test "it states its bounds, its step and what the value means", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      slider = live |> player() |> element("#transport-position") |> render()

      # The small step is the one a key press repeats; §20 holds both figures.
      assert slider =~ ~s|min="0"|
      assert slider =~ ~s|step="10000"|

      # The readable value is in aria-valuetext rather than the name, so it is announced
      # on every change rather than once when the control is reached.
      assert slider =~ "aria-valuetext"
      assert slider =~ "0:00 of"
    end

    test "a holding carried by its own file states its recorded length", %{conn: conn} do
      # spec-01 §8.4's recorded figure, which is what §13.2 measures against. A file
      # with no album beside its title is a release of its own, so the entry played here
      # is carried by one file and nothing else.
      recording = a_recording(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{recording}"]|) |> render_click()

      slider = live |> player() |> element("#transport-position") |> render()

      refute slider =~ "disabled"
      assert slider =~ ~s|max="2000"|
      assert slider =~ "0:00 of 0:02"
    end

    test "§17.3. Every control that acts on the element is bound to it", %{conn: conn} do
      # The binding rather than the markup: a control that exists by name and is wired
      # to nothing is what §17.3 forbids.
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      bar = live |> player() |> element("#transport") |> render()

      for acted_on <- ~w(transport-position transport-back transport-forward
                         transport-volume transport-mute) do
        assert bar =~ ~s|id="#{acted_on}"|
      end

      assert bar =~ ~s|phx-hook="MediaSession"|
      assert bar =~ ~s|data-step="60000"|
    end

    test "the large step is a control of its own in each direction, naming its interval",
         %{conn: conn} do
      # §17.5 forbids a function that requires dragging, and §12.3 forbids the slider
      # being the only way to seek.
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      assert has_element?(player(live), ~s|button[aria-label="Back 60 seconds"]|)
      assert has_element?(player(live), ~s|button[aria-label="Forward 60 seconds"]|)
    end

    test "the slider is not inside the live region", %{conn: conn} do
      # §12.3 says so in those words: a position announced as it advanced would talk
      # over everything else the region has to say.
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      refute has_element?(live, "#shell-announcement #transport-position")
    end
  end

  describe "criterion 40. A track of a one-file release plays as a region of it" do
    test "both tracks name one file and differ only in where they begin and end",
         %{conn: conn} do
      # A track is reached through the queue rather than through a row: its release
      # aggregates it, so §8.1 makes the release the browse entry and not the track.
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      first = live |> player() |> element("#transport-medium") |> render()

      live |> player() |> element(~s|button[phx-click="transport-next"]|) |> render_click()

      second = live |> player() |> element("#transport-medium") |> render()

      assert first =~ ~s|data-from="0"|
      assert first =~ ~s|data-to="3000"|
      assert second =~ ~s|data-from="3000"|
      assert second =~ ~s|data-to="6000"|

      assert asset_of(first) == asset_of(second),
             "the two tracks were served as two streams rather than one region each"
    end
  end

  describe "§12.3. The queue is the principal's own, and jumping to an entry moves it" do
    test "it lists every entry and says which is current", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()
      live |> player() |> element(~s|button[phx-click="transport-queue"]|) |> render_click()

      queue = live |> player() |> element("#transport-queue") |> render()

      assert queue =~ "So What"
      assert queue =~ "Freddie Freeloader"
      assert has_element?(player(live), ~s|#transport-queue button[aria-current="true"]|)
    end

    test "jumping to an entry makes it the one playing", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()
      live |> player() |> element(~s|button[phx-click="transport-queue"]|) |> render_click()

      live |> player() |> element(~s|button[phx-value-index="1"]|) |> render_click()

      assert live |> player() |> element("#transport-medium") |> render() =~ ~s|data-from="3000"|
    end

    test "the first entry cannot be gone back from and the last cannot be gone on from",
         %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      assert has_element?(player(live), ~s|button[phx-click="transport-previous"][disabled]|)
      refute has_element?(player(live), ~s|button[phx-click="transport-next"][disabled]|)

      live |> player() |> element(~s|button[phx-click="transport-next"]|) |> render_click()

      assert has_element?(player(live), ~s|button[phx-click="transport-next"][disabled]|)
      refute has_element?(player(live), ~s|button[phx-click="transport-previous"][disabled]|)
    end
  end

  describe "§12.4. At the end the next member is offered, and nothing begins unasked" do
    test "the offer names what is next and how long it has", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      finished(live)

      offer = live |> player() |> element("#transport-offer") |> render()

      assert offer =~ "Freddie Freeloader"
      assert offer =~ "10 seconds"
      assert has_element?(player(live), ~s|button[phx-click="transport-offer-cancel"]|)
    end

    test "the offer leaves it paused, so audio does not begin unasked", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      finished(live)

      assert has_element?(player(live), ~s|button[aria-label="Play"][phx-click="transport-play"]|)
    end

    test "taking the offer is the person asking, so that one plays", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      finished(live)
      live |> player() |> element(~s|button[phx-click="transport-offer-take"]|) |> render_click()

      refute has_element?(player(live), "#transport-offer")
      assert has_element?(player(live), ~s|button[aria-label="Pause"]|)
      assert live |> player() |> element("#transport-medium") |> render() =~ ~s|data-from="3000"|
    end

    test "cancelling it withdraws the offer and moves nothing", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      finished(live)

      live
      |> player()
      |> element(~s|button[phx-click="transport-offer-cancel"]|)
      |> render_click()

      refute has_element?(player(live), "#transport-offer")
      assert live |> player() |> element("#transport-medium") |> render() =~ ~s|data-from="0"|
    end

    test "a principal who turned the offer off is not offered one",
         %{conn: conn, subject: subject} do
      # §12.4 requires the offer be disableable per principal, and the preference store
      # is where that choice lives.
      %{release: release} = a_release(conn)

      # The proxy admits an identity on its first request, so the principal exists only
      # once a surface has been reached as them.
      {:ok, _live, _html} = live(conn, ~p"/everything")
      principal = Principals.principal_for(issuer(), subject)

      {:ok, _} = Preferences.set(principal.id, "next_member_offer", "off")

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      finished(live)

      refute has_element?(player(live), "#transport-offer")
    end
  end

  # The player is a LiveView of its own, rendered sticky inside whatever surface is up,
  # so its controls are addressed through the child rather than the page around it.
  defp player(live), do: find_live_child(live, "transport-live")

  defp finished(live) do
    res = live |> player() |> element("#transport-medium") |> render() |> res_of()

    render_hook(element(player(live), "#transport"), "transport-finished", %{"res" => res})
  end

  defp reported(live, position_ms) do
    res = live |> player() |> element("#transport-medium") |> render() |> res_of()

    render_hook(element(player(live), "#transport"), "transport-position", %{
      "res" => res,
      "position_ms" => position_ms
    })
  end

  defp res_of(html) do
    [_whole, res] = Regex.run(~r/data-res="([^"]+)"/, html)

    res
  end

  defp asset_of(html) do
    [_whole, asset] = Regex.run(~r|/assets/([^/]+)/content|, html)

    asset
  end

  # A release whose files name an album artist, so placement writes a credit and the
  # surfaces have somebody to say it is by.
  defp a_credited_release(_conn) do
    inbox = inbox!()
    prefix = unique_prefix()

    tags = %{"album" => "Kind of Blue", "album_artist" => "Miles Davis"}

    placed =
      ingest!(inbox, %{
        "#{prefix}/01 So What.flac" =>
          media!(:flac, duration: 2, tags: Map.put(tags, "title", "So What")),
        "#{prefix}/02 Freddie.flac" =>
          media!(:flac, duration: 2, tags: Map.put(tags, "title", "Freddie"))
      })

    track =
      placed
      |> hd()
      |> then(&Repo.get!(DigitalItem, &1.digital_item_id).manifestation_id)
      |> work_of()

    %{release: Grouping.grouping_of(track)}
  end

  # A holding carried by its own file: one asset, no region, and a length placement read
  # from the probe and recorded against the manifestation.
  #
  # A file with no album beside its title is a release of its own, so the entry a surface
  # offers is the release above the track rather than the track the file became.
  defp a_recording(_conn) do
    inbox = inbox!()
    prefix = unique_prefix()

    [placed] =
      ingest!(inbox, %{
        "#{prefix}/alone.flac" => media!(:flac, duration: 2, tags: %{"title" => "Blue in Green"})
      })

    track =
      placed.digital_item_id
      |> then(&Repo.get!(DigitalItem, &1).manifestation_id)
      |> work_of()

    Grouping.grouping_of(track)
  end

  # A release held in one file, so its tracks are regions of the release's own bytes and
  # criterion 40 is what makes them playable at all.
  defp a_release(_conn) do
    inbox = inbox!()
    prefix = unique_prefix()

    placed =
      ingest!(inbox, %{
        "#{prefix}/album.flac" => media!(:flac, duration: 6),
        "#{prefix}/album.cue" => """
        TITLE "Kind of Blue"
        PERFORMER "Miles Davis"
        FILE "album.flac" WAVE
          TRACK 01 AUDIO
            TITLE "So What"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Freddie Freeloader"
            INDEX 01 00:03:00
        """
      })

    album = Enum.find(placed, &(&1.media_class == :audio))
    release = Repo.get!(DigitalItem, album.digital_item_id).manifestation_id

    [%{part_id: medium}] = Catalog.parts_of(release)
    parts = Catalog.parts_of(medium)

    %{
      release: work_of(release),
      tracks: Enum.map(parts, &work_of(&1.part_id))
    }
  end

  defp work_of(manifestation_id) do
    [expression | _rest] = Catalog.expressions_in(manifestation_id)

    expression.work_id
  end

  defp ingest!(inbox, files) do
    for {path, bytes} <- files, do: drop!(inbox, path, bytes)

    ids = inbox |> acquire_settled!() |> acquired()

    place_all!(inbox)
    Normalize.normalize_due()

    ids |> Enum.map(&Ingest.get_acquisition!/1) |> Enum.sort_by(& &1.inbox_path)
  end
end
