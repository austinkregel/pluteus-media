defmodule PluteusWeb.FindingsEquationTest do
  @moduledoc """
  An equation matching performed is reported on the findings surface and undone from it
  ([spec-05] §8.4, criterion 18; [spec-10] §16.1).

  Two tracks of one recording are placed by the real pipeline and equated against a small
  MusicBrainz dump imported the way a real one is.

  Not async: holding a snapshot exchanges the `musicbrainz` schema itself.
  """

  use PluteusWeb.ConnCase, async: false

  import Pluteus.IngestFixtures
  import Pluteus.MusicBrainzFixtures

  alias Pluteus.Catalog
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Corpus
  alias Pluteus.Dedup.Candidate
  alias Pluteus.Ingest
  alias Pluteus.Lifecycle
  alias Pluteus.Matching.Music
  alias Pluteus.Principals
  alias Pluteus.Repo

  @t0 ~U[2026-11-07 12:00:00.000000Z]

  @song "8f3471b5-7e6a-48da-86a9-c1c07a0f47ae"
  @album "a1b2c3d4-e5f6-4789-8abc-def012345678"
  @compilation "b2c3d4e5-f6a7-4890-9bcd-ef0123456789"

  setup %{conn: conn} do
    _system = Principals.system!()
    on_exit(fn -> File.rm_rf!(Path.join(Corpus.directory(), "musicbrainz")) end)

    held!(%{
      "recording" => [recording(1, @song, "Song")],
      "release" => [
        release(10, @album, 100, "Album"),
        release(11, @compilation, 101, "Compilation")
      ]
    })

    inbox = inbox!()
    prefix = unique_prefix()

    for {path, album, release, frequency} <- [
          {"album/song.flac", "Album", @album, 440},
          {"compilation/song.flac", "Compilation", @compilation, 660}
        ] do
      tags = %{
        "album" => album,
        "album_artist" => "An artist",
        "track" => "1",
        "musicbrainz_albumid" => release,
        "musicbrainz_trackid" => @song
      }

      drop!(inbox, Path.join(prefix, path), media!(:flac, frequency: frequency, tags: tags))
    end

    ids = inbox |> acquire_settled!(@t0) |> acquired()
    place_all!(inbox)

    [album, compilation] =
      ids |> Enum.map(&Ingest.get_acquisition!/1) |> Enum.sort_by(& &1.inbox_path)

    conn =
      conn
      |> through_proxy(a_subject())
      |> on_a_surface()
      |> Plug.Conn.put_req_header("accept", "text/html")

    %{conn: conn, album: album, compilation: compilation}
  end

  defp expressions(acquisition) do
    acquisition.digital_item_id
    |> then(&Repo.get!(DigitalItem, &1).manifestation_id)
    |> Catalog.expressions_in()
  end

  test "the report says what was equated, and undoing it separates the two again", %{
    conn: conn,
    album: album,
    compilation: compilation
  } do
    [compiled] = expressions(compilation)

    Music.key_due()
    Music.resolve_due()
    Music.apply_due()

    assert expressions(compilation) == expressions(album)
    [report] = Enum.filter(Ingest.open_findings(), &(&1.kind == "equated"))

    {:ok, live, html} = live(conn, ~p"/findings")
    assert html =~ "equated"
    assert html =~ "stands until cleared"

    html = live |> element("#undo-equation-#{report.id}") |> render_click()

    assert expressions(compilation) == [compiled]
    assert {:live, _} = Lifecycle.state(compiled.id)
    assert Repo.get!(Candidate, report.detail["candidate"]).decision == :distinct
    assert html =~ "Nothing is outstanding."
  end
end
