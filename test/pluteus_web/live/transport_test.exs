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
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Preferences
  alias Pluteus.Principals
  alias Pluteus.Repo

  setup %{conn: conn} do
    subject = a_subject()

    %{conn: conn |> through_proxy(subject) |> on_a_surface(), subject: subject}
  end

  describe "§12.3. Nothing current means no transport" do
    test "the bar is absent before anything is played", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/everything")

      refute has_element?(live, "#transport")
    end
  end

  describe "§12.3. Every control states the action it will perform" do
    test "playing a holding draws the bar, named, with a pause control", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")

      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      assert has_element?(live, "#transport")
      assert has_element?(live, ~s|button[aria-label="Pause"]|)
      refute has_element?(live, ~s|button[aria-label="Play"][phx-click="transport-play"]|)
    end

    test "pausing it offers to play again", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")

      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()
      live |> element(~s|button[aria-label="Pause"]|) |> render_click()

      assert has_element?(live, ~s|button[aria-label="Play"][phx-click="transport-play"]|)
    end
  end

  describe "§12.3. The position slider carries both granularities and a spoken value" do
    test "it states its bounds, its step and what the value means", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      slider = live |> element("#transport-position") |> render()

      # The small step is the one a key press repeats; §20 holds both figures.
      assert slider =~ ~s|min="0"|
      assert slider =~ ~s|step="10000"|

      # The readable value is in aria-valuetext rather than the name, so it is announced
      # on every change rather than once when the control is reached.
      assert slider =~ "aria-valuetext"
      assert slider =~ "0:00 of"
    end

    test "the large step is a control of its own in each direction, naming its interval",
         %{conn: conn} do
      # §17.5 forbids a function that requires dragging, and §12.3 forbids the slider
      # being the only way to seek.
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      assert has_element?(live, ~s|button[aria-label="Back 60 seconds"]|)
      assert has_element?(live, ~s|button[aria-label="Forward 60 seconds"]|)
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

      first = live |> element("#transport-medium") |> render()

      live |> element(~s|button[phx-click="transport-next"]|) |> render_click()

      second = live |> element("#transport-medium") |> render()

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
      live |> element(~s|button[phx-click="transport-queue"]|) |> render_click()

      queue = live |> element("#transport-queue") |> render()

      assert queue =~ "So What"
      assert queue =~ "Freddie Freeloader"
      assert has_element?(live, ~s|#transport-queue button[aria-current="true"]|)
    end

    test "jumping to an entry makes it the one playing", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()
      live |> element(~s|button[phx-click="transport-queue"]|) |> render_click()

      live |> element(~s|button[phx-value-index="1"]|) |> render_click()

      assert live |> element("#transport-medium") |> render() =~ ~s|data-from="3000"|
    end

    test "the first entry cannot be gone back from and the last cannot be gone on from",
         %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      assert has_element?(live, ~s|button[phx-click="transport-previous"][disabled]|)
      refute has_element?(live, ~s|button[phx-click="transport-next"][disabled]|)

      live |> element(~s|button[phx-click="transport-next"]|) |> render_click()

      assert has_element?(live, ~s|button[phx-click="transport-next"][disabled]|)
      refute has_element?(live, ~s|button[phx-click="transport-previous"][disabled]|)
    end
  end

  describe "§12.4. At the end the next member is offered, and nothing begins unasked" do
    test "the offer names what is next and how long it has", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      finished(live)

      offer = live |> element("#transport-offer") |> render()

      assert offer =~ "Freddie Freeloader"
      assert offer =~ "10 seconds"
      assert has_element?(live, ~s|button[phx-click="transport-offer-cancel"]|)
    end

    test "the offer leaves it paused, so audio does not begin unasked", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      finished(live)

      assert has_element?(live, ~s|button[aria-label="Play"][phx-click="transport-play"]|)
    end

    test "taking the offer is the person asking, so that one plays", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      finished(live)
      live |> element(~s|button[phx-click="transport-offer-take"]|) |> render_click()

      refute has_element?(live, "#transport-offer")
      assert has_element?(live, ~s|button[aria-label="Pause"]|)
      assert live |> element("#transport-medium") |> render() =~ ~s|data-from="3000"|
    end

    test "cancelling it withdraws the offer and moves nothing", %{conn: conn} do
      %{release: release} = a_release(conn)

      {:ok, live, _html} = live(conn, ~p"/everything?category=album")
      live |> element(~s|button[phx-value-res="#{release}"]|) |> render_click()

      finished(live)
      live |> element(~s|button[phx-click="transport-offer-cancel"]|) |> render_click()

      refute has_element?(live, "#transport-offer")
      assert live |> element("#transport-medium") |> render() =~ ~s|data-from="0"|
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

      refute has_element?(live, "#transport-offer")
    end
  end

  defp finished(live) do
    res = live |> element("#transport-medium") |> render() |> res_of()

    render_hook(element(live, "#transport-medium"), "transport-finished", %{"res" => res})
  end

  defp res_of(html) do
    [_whole, res] = Regex.run(~r/data-res="([^"]+)"/, html)

    res
  end

  defp asset_of(html) do
    [_whole, asset] = Regex.run(~r|/assets/([^/]+)/content|, html)

    asset
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
