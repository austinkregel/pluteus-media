defmodule Pluteus.Ingest.PlacementTest do
  @moduledoc """
  Placement: spec-04 §6 and the conformance criteria it carries. Each
  `describe` names its criterion.
  """

  use Pluteus.DataCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Actor
  alias Pluteus.Annotations
  alias Pluteus.Assets
  alias Pluteus.Browse.Entries
  alias Pluteus.Browse.Query
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Addressing
  alias Pluteus.Catalog.Aggregation
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.DeepLink
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Refinements
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Work
  alias Pluteus.Dedup
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Credits
  alias Pluteus.Ingest.NarrationKey
  alias Pluteus.Ingest.Place
  alias Pluteus.Ingest.Registry
  alias Pluteus.Ingest.ReleaseKey
  alias Pluteus.Ingest.Streams
  alias Pluteus.Ingest.TimeSpanKey
  alias Pluteus.Lifecycle
  alias Pluteus.PlatformEvents
  alias Pluteus.Presentation.Geometry
  alias Pluteus.Principals
  alias Pluteus.Storage
  alias Pluteus.StorageFixtures

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup do
    system = Principals.system!()
    %{inbox: inbox!(), system: system}
  end

  describe "placement announces the holding to the household ([spec-01] §11.2)" do
    test "a placed holding is a platform event of the System principal's",
         %{inbox: inbox, system: system} do
      [acquisition] = ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png)})
      digital_item_id = Repo.get!(Acquisition, acquisition.id).digital_item_id

      assert [%{type: "placed", res_id: res_id, recorded_by: by}] =
               PlatformEvents.about(digital_item_id)

      assert res_id == digital_item_id
      assert by == system.id
    end
  end

  describe "1. Once placed, a file is an asset with the acquisition's identifier and name" do
    test "the asset takes the identifier and the name it arrived under", %{inbox: inbox} do
      [acquisition] = ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png)})

      asset = Repo.get!(Asset, acquisition.id)
      assert asset.location == acquisition.location
      assert asset.digest == acquisition.digest
      assert ["IMG_0001.png"] = names(asset.id)
    end

    test "the asset is verified at the interval configured for its broad class",
         %{inbox: inbox} do
      [photo] = ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png)})

      configured =
        :pluteus
        |> Application.fetch_env!(Ingest)
        |> Keyword.fetch!(:verification_interval_seconds)

      assert Repo.get!(Asset, photo.id).verification_interval_seconds == configured.image
    end

    test "the probe's reading becomes a derived annotation on the asset it read",
         %{inbox: inbox} do
      [track] = ingest!(inbox, %{"KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1))})

      # §6.1. The asset takes the acquisition's identifier, so the probe's input is
      # the acquisition's own id, and spec-02 §4.1's "res the tool ran over" is the
      # file rather than the manifestation over it.
      assert [%{body_type: "probe", body: body, derivation_id: derivation_id}] =
               Annotations.current_on(track.id)

      assert body == track.probe
      assert Annotations.current_derivation("ffprobe", track.id).id == derivation_id
      assert Annotations.current_on(manifestation_of(track)) == []
    end

    test "a second asset of one digital item keeps its own reading", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1))})
      version = Streams.ffprobe_version()

      {:ok, %{asset: part_two}} =
        Catalog.create_asset(
          track.digital_item_id,
          %{
            location: StorageFixtures.stored!("02.png", StorageFixtures.png("part two")),
            essence: :lossless,
            verification_interval_seconds: 86_400,
            roles: [%{role_class: :acquired, role: "original"}]
          },
          "02.flac"
        )

      {:ok, derivation} =
        Annotations.record_derivation(%{
          tool: "ffprobe",
          version: version,
          input_id: part_two.id,
          parameters: %{},
          derived_at: DateTime.utc_now()
        })

      {:ok, _} =
        Annotations.annotate(%{
          target_id: part_two.id,
          body_type: "probe",
          body: %{"format" => %{"duration" => "9.0"}},
          derivation_id: derivation.id
        })

      # Both readings are ffprobe's at one version. Keyed on the manifestation the
      # two assets share, the second would be the current run and the first would be
      # retained as superseded; keyed on each asset, each is current over its own
      # input and nothing is lost.
      assert [_] = Annotations.current_on(track.id)
      assert [_] = Annotations.current_on(part_two.id)
      assert Annotations.superseded_on(track.id) == []
      assert Annotations.current_derivation("ffprobe", track.id).input_id == track.id
      assert Annotations.current_derivation("ffprobe", part_two.id).input_id == part_two.id
    end
  end

  describe "the category without evidence is the broad class's (§6.3)" do
    test "each class takes its default", %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1)),
          "holiday/IMG_0001.png" => media!(:png),
          "home/birthday.mkv" => media!(:ffv1),
          "letters/note.txt" => "a note\n"
        })

      categories =
        Map.new(
          placed,
          &{&1.inbox_path, Catalog.category_of(work_of(&1), Place.category_scheme())}
        )

      assert categories == %{
               "KoB/01.flac" => "music_recording",
               "holiday/IMG_0001.png" => "photograph",
               "home/birthday.mkv" => "home_video",
               "letters/note.txt" => "document"
             }

      track = Enum.find(placed, &(&1.inbox_path == "KoB/01.flac"))
      assert Catalog.category_of(work_of_release(track), Place.category_scheme()) == "album"
    end
  end

  describe "the category from the file's own tags outranks the class default (§6.3)" do
    test "a genre the registry names decides the category", %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "spoken/chapter-01.flac" => media!(:flac, tags: %{"genre" => "Audiobook"}),
          "shows/episode-12.flac" => media!(:flac, tags: %{"genre" => "Podcast"}),
          "KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1))
        })

      assert categories(placed) == %{
               "spoken/chapter-01.flac" => "audiobook",
               "shows/episode-12.flac" => "podcast_episode",
               "KoB/01.flac" => "music_recording"
             }
    end

    test "the value is matched whole and case-folded, never as a substring",
         %{inbox: inbox} do
      # A substring match would make "Podcast Theme Music" a podcast episode. The
      # class default answers instead, and §6.2's correction surface is what a
      # member reaches for when it is wrong.
      placed =
        ingest!(inbox, %{
          "a/loud.flac" => media!(:flac, tags: %{"genre" => "AUDIOBOOK"}),
          "b/wide.flac" => media!(:flac, tags: %{"genre" => "Audiobooks & Spoken Word"}),
          "c/theme.flac" => media!(:flac, tags: %{"genre" => "Podcast Theme Music"})
        })

      assert categories(placed) == %{
               "a/loud.flac" => "audiobook",
               "b/wide.flac" => "music_recording",
               "c/theme.flac" => "music_recording"
             }
    end

    test "a rule decides only for the broad classes it names", %{inbox: inbox} do
      # An audiobook is audio. A still image whose genre tag reads Audiobook is a
      # photograph, because the class the bytes decided rules the tag out.
      placed = ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png)})

      assert categories(placed) == %{"holiday/IMG_0001.png" => "photograph"}
      refute Registry.category_from_tags(:image, %{"genre" => "audiobook"})
      assert Registry.category_from_tags(:audio, %{"genre" => "audiobook"}) == "audiobook"
    end

    test "a tag the registry does not name decides nothing" do
      assert Registry.category_from_tags(:audio, %{}) == nil
      assert Registry.category_from_tags(:audio, %{"mood" => "audiobook"}) == nil
      assert Registry.category_from_tags(:audio, %{"genre" => "Jazz"}) == nil
    end
  end

  describe "the category from a document beside the holding (§6.3)" do
    # The shape Sonarr writes beside an episode, which is the only thing that says what
    # the file is: the container states no title, no show and no number.
    defp episode_document(series, season, episode, name) do
      """
      <details>
        <id>90</id>
        <title>#{series} - #{season}x#{episode} - #{name}</title>
        <series_name>#{series}</series_name>
        <episode_name>#{name}</episode_name>
        <season_number>#{season}</season_number>
        <episode_number>#{episode}</episode_number>
        <firstaired>2022-07-05</firstaired>
      </details>
      """
    end

    test "a document naming the file decides what the file is", %{inbox: inbox} do
      prefix = unique_prefix()

      placed =
        ingest!(inbox, %{
          "#{prefix}/Overlord - S04E01.mkv" => media!(:film),
          "#{prefix}/Overlord - S04E01.xml" =>
            episode_document("Overlord", "04", "01", "Sorcerer")
        })

      assert categories(placed)["#{prefix}/Overlord - S04E01.mkv"] == "television_episode"
    end

    test "the episode is placed within the series the document names", %{inbox: inbox} do
      prefix = unique_prefix()

      [episode, _document] =
        ingest!(inbox, %{
          "#{prefix}/Overlord - S04E01.mkv" => media!(:film),
          "#{prefix}/Overlord - S04E01.xml" =>
            episode_document("Overlord", "04", "01", "Sorcerer")
        })

      assert names(series_of(episode)) == ["Overlord"]

      # The document states both figures, so the season is the stride and the episode
      # sits within it.
      assert [%{position: 4001}] = Catalog.parts_of(serial_manifestation(episode))
    end

    test "a document about what the holding belongs to does not say what it is",
         %{inbox: inbox} do
      # An album document dates the release. A track beside it is a music recording, and
      # a document that decided the holding's category would make every track an album.
      prefix = unique_prefix()

      album = """
      <album>
        <title>In Keeping Secrets of Silent Earth: 3</title>
        <releasedate>03/30/2003</releasedate>
        <label>Equal Vision Records</label>
      </album>
      """

      placed =
        ingest!(inbox, %{
          "#{prefix}/01.flac" => media!(:flac, tags: album("In Keeping Secrets", 1)),
          "#{prefix}/album.nfo" => album
        })

      assert categories(placed)["#{prefix}/01.flac"] == "music_recording"
    end

    # §4.6 already tells a media manager's document from a release's notes by its root.
    test "a root the registry does not name states nothing", %{inbox: inbox} do
      prefix = unique_prefix()

      placed =
        ingest!(inbox, %{
          "#{prefix}/birthday.mkv" => media!(:film),
          "#{prefix}/birthday.nfo" => "Released by SOMEGROUP\nNot markup at all\n"
        })

      assert categories(placed)["#{prefix}/birthday.mkv"] == "home_video"
    end

    # The nearer statement about a thing is the one to believe.
    test "what a file says about itself outranks a document beside it", %{inbox: inbox} do
      prefix = unique_prefix()

      placed =
        ingest!(inbox, %{
          "#{prefix}/talk.flac" => media!(:flac, tags: %{"genre" => "Audiobook"}),
          "#{prefix}/talk.xml" => episode_document("Ologies", "01", "02", "Talk")
        })

      assert categories(placed)["#{prefix}/talk.flac"] == "audiobook"
    end
  end

  describe "a match file names a show and says which episode each file is (§6.3)" do
    # The shape Plex writes at the top of a show: the show's own fields, then one line
    # per file naming it by path relative to the match file's own directory.
    defp match_file(show, episodes) do
      lines =
        for {season, episode, path} <- episodes,
            do: "Episode: S#{season}E#{episode}: #{path}"

      Enum.join(["Title: #{show}", "Year: 1997", "TvdbId: 73903" | lines], "\n") <> "\n"
    end

    defp only_media(placed), do: Enum.find(placed, &(&1.media_class != :companion))

    test "a file the match file names is an episode of the show it names", %{inbox: inbox} do
      prefix = unique_prefix()

      episode =
        ingest!(inbox, %{
          "#{prefix}/Season 11/1101 - The Peggy Horror Picture Show.mkv" => media!(:film),
          "#{prefix}/.plexmatch" =>
            match_file("King of the Hill", [
              {"11", "01", "Season 11/1101 - The Peggy Horror Picture Show.mkv"}
            ])
        })
        |> only_media()

      assert Catalog.category_of(work_of(episode), Place.category_scheme()) ==
               "television_episode"

      assert names(series_of(episode)) == ["King of the Hill"]
    end

    # The season and the episode are both stated, and the arrangement is one integer, so
    # the season is the stride the registry names and the episode sits within it.
    test "the season and the episode together are where it sits", %{inbox: inbox} do
      prefix = unique_prefix()

      episode =
        ingest!(inbox, %{
          "#{prefix}/Season 11/1101 - The Peggy Horror Picture Show.mkv" => media!(:film),
          "#{prefix}/.plexmatch" =>
            match_file("King of the Hill", [
              {"11", "01", "Season 11/1101 - The Peggy Horror Picture Show.mkv"}
            ])
        })
        |> only_media()

      assert [%{position: 11_001}] = Catalog.parts_of(serial_manifestation(episode))
    end

    # A match file is the only document that reaches past its own directory, and it does
    # so only for a file it names.
    test "a file the match file does not name is not spoken for", %{inbox: inbox} do
      prefix = unique_prefix()

      placed =
        ingest!(inbox, %{
          "#{prefix}/Season 11/1101 - Named.mkv" => media!(:film),
          "#{prefix}/Season 11/1102 - Unnamed.mkv" => media!(:film),
          "#{prefix}/.plexmatch" =>
            match_file("King of the Hill", [{"11", "01", "Season 11/1101 - Named.mkv"}])
        })

      assert categories(placed)["#{prefix}/Season 11/1101 - Named.mkv"] == "television_episode"
      assert categories(placed)["#{prefix}/Season 11/1102 - Unnamed.mkv"] == "home_video"
    end

    # A serial is ordered where it says it is, and a line stating a season and no episode
    # states only the season.
    test "a line stating no episode leaves the file unnumbered", %{inbox: inbox} do
      prefix = unique_prefix()

      episode =
        ingest!(inbox, %{
          "#{prefix}/Specials/Clementine Part 1.mkv" => media!(:film),
          "#{prefix}/.plexmatch" =>
            "Title: Overlord\nEpisode: S01: Specials/Clementine Part 1.mkv\n"
        })
        |> only_media()

      assert [%{position: nil}] = Catalog.parts_of(serial_manifestation(episode))
    end

    test "a path numbers nothing, so a file name beginning with digits is not a position",
         %{inbox: inbox} do
      # Within one show, episodes a match file numbers by season and episode would
      # otherwise sort against episodes numbered from their file names.
      episode = an_episode(inbox, "Pinwheel", "Season 01/101 - Pilot.mkv")

      assert [%{position: nil}] = Catalog.parts_of(serial_manifestation(episode))
    end
  end

  describe "the category from where a household filed a holding (§6.3)" do
    test "a video filed under television is an episode and not a home video",
         %{inbox: inbox} do
      # The class default for video is a home video, and a rip states nothing about
      # itself: the directory is the household saying what it is.
      placed = ingest!(inbox, %{"TV/Pinwheel/Season 01/101 - Pilot.mkv" => media!(:film)})

      assert categories(placed) == %{
               "TV/Pinwheel/Season 01/101 - Pilot.mkv" => "television_episode"
             }
    end

    test "the segment is matched whole and case-folded, never as a substring",
         %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "tv/Pinwheel/101 - Pilot.mkv" => media!(:film),
          "TV Rips/Pinwheel/101 - Pilot.mkv" => media!(:film)
        })

      assert categories(placed) == %{
               "tv/Pinwheel/101 - Pilot.mkv" => "television_episode",
               "TV Rips/Pinwheel/101 - Pilot.mkv" => "home_video"
             }
    end

    test "a rule decides only for the broad classes it names", %{inbox: inbox} do
      # A still sitting beside the episodes is an image. A rule that read the directory
      # alone would make it an episode of the series.
      placed = ingest!(inbox, %{"TV/Pinwheel/the cast.png" => media!(:png)})

      assert categories(placed) == %{"TV/Pinwheel/the cast.png" => "photograph"}
    end

    test "what a file states about itself outranks where it was filed", %{inbox: inbox} do
      placed =
        ingest!(inbox, %{"TV/Ologies/12.flac" => media!(:flac, tags: %{"genre" => "Podcast"})})

      assert categories(placed) == %{"TV/Ologies/12.flac" => "podcast_episode"}
    end

    test "a path naming nothing the registry holds states nothing" do
      assert Registry.path_evidence("holiday/IMG_0001.jpg", :image) == nil
      assert Registry.path_evidence("TV/Pinwheel/101 - Pilot.mkv", :audio) == nil

      assert %{category: "television_episode", serial_name: "Pinwheel"} =
               Registry.path_evidence("TV/Pinwheel/Season 01/101 - Pilot.mkv", :video)
    end
  end

  describe "§6.9. An episode is a work positioned within the series the path names" do
    defp an_episode(inbox, show, file_name) do
      prefix = unique_prefix()

      [episode] = ingest!(inbox, %{"#{prefix}/TV/#{show}/#{file_name}" => media!(:film)})

      episode
    end

    test "the directory above the seasons names the series", %{inbox: inbox} do
      episode = an_episode(inbox, "Pinwheel", "Season 01/101 - Pilot.mkv")
      series = series_of(episode)

      assert Catalog.category_of(series, Place.category_scheme()) == "television_series"
      assert names(series) == ["Pinwheel"]
    end

    test "two episodes of one show find one series", %{inbox: inbox} do
      first = an_episode(inbox, "Pinwheel", "Season 01/101 - Pilot.mkv")
      second = an_episode(inbox, "Pinwheel", "Season 01/102 - Square Peg.mkv")

      assert series_of(first) == series_of(second)
      assert [%{position: nil}, %{position: nil}] = Catalog.parts_of(serial_manifestation(first))
    end

    test "a video filed under no series is placed on its own", %{inbox: inbox} do
      prefix = unique_prefix()

      [video] = ingest!(inbox, %{"#{prefix}/birthday.mkv" => media!(:film)})

      assert Catalog.inspirations_of(work_of(video)) == []
      assert Catalog.wholes_of(manifestation_of(video)) == []
    end
  end

  describe "placement records how much of the holding there is (spec-01 §8.4)" do
    test "a sounding holding carries its duration on the manifestation", %{inbox: inbox} do
      [track] =
        ingest!(inbox, %{
          "KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1), duration: 3)
        })

      extent = Addressing.get_extent(manifestation_of(track), :millisecond)

      assert extent.magnitude == Streams.duration_ms(track.probe)
      assert_in_delta extent.magnitude, 3_000, 200
    end

    test "a moving holding carries one too", %{inbox: inbox} do
      [film] = ingest!(inbox, %{"home/birthday.mkv" => media!(:ffv1)})

      assert Addressing.get_extent(manifestation_of(film), :millisecond).magnitude > 0
    end

    test "a still holding carries none: there is no length to be part way through",
         %{inbox: inbox} do
      [photo] = ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png)})

      assert Addressing.get_extent(manifestation_of(photo), :millisecond) == nil
    end

    test "the figure is what a position within the holding is a fraction of",
         %{inbox: inbox} do
      [track] =
        ingest!(inbox, %{
          "KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1), duration: 4)
        })

      manifestation = manifestation_of(track)
      whole = Addressing.get_extent(manifestation, :millisecond).magnitude

      {:ok, %{address: address}} =
        Catalog.create_address(manifestation, %{
          selector_type: :temporal,
          start_ms: div(whole, 4),
          end_ms: div(whole, 2)
        })

      {start_at, end_at} = Addressing.normalized_position(address)

      assert_in_delta start_at, 0.25, 0.01
      assert_in_delta end_at, 0.5, 0.01
    end
  end

  defp categories(placed) do
    Map.new(
      placed,
      &{&1.inbox_path, Catalog.category_of(work_of(&1), Place.category_scheme())}
    )
  end

  describe "5. A file dropped again after its holding was recycled is a new acquisition" do
    test "bringing back something deleted acquires it", %{inbox: inbox, actor: actor} do
      bytes = media!(:png)
      [first] = ingest!(inbox, %{"holiday/IMG_0001.png" => bytes})
      {:ok, _} = Lifecycle.recycle(first.digital_item_id, actor.id)

      drop!(inbox, "holiday/IMG_0001.png", bytes)

      assert [_again] = inbox |> acquire_settled!(DateTime.add(@t0, 3_600)) |> acquired()
      assert [_, _] = Ingest.acquisitions_from("holiday/IMG_0001.png")
    end
  end

  describe "6. An asset's location does not change when the holding is renamed or re-placed" do
    test "renaming and moving under another expression leave the bytes where they lie",
         %{inbox: inbox, actor: actor} do
      [first, second] =
        ingest!(inbox, %{
          "letters/1943-04-12.png" => media!(:png),
          "letters/1943-04-12 rescan.png" => media!(:jpeg)
        })

      location = Repo.get!(Asset, second.id).location

      {:ok, _} = Catalog.create_nomen(%{res_id: second.id, nomen_string: "Letter from Ada"})
      {:ok, candidate} = Dedup.propose(first.digital_item_id, second.digital_item_id, actor.id)
      {:ok, _} = Dedup.decide(candidate.id, :same_expression, actor.id)

      assert Repo.get!(Asset, second.id).location == location
      assert Storage.exists?(location)
    end
  end

  describe "36. A comic archive is one digital item, its pages selectors on it" do
    defp a_comic(inbox, pages) do
      entries = for n <- 1..pages, do: {"page-#{n}.png", comic_page(n)}
      prefix = unique_prefix()

      [comic] = ingest!(inbox, %{"#{prefix}/Excitebike Weekly 001.cbz" => cbz(entries)})

      comic
    end

    test "the archive is one holding, not one per page", %{inbox: inbox} do
      comic = a_comic(inbox, 3)

      assert comic.media_class == :package
      assert Catalog.category_of(work_of(comic), Place.category_scheme()) == "comic_issue"

      # One digital item carrying one asset: the archive itself. That `ingest!` returned a
      # single acquisition is the rest of it — no page became a holding of its own, because
      # only the file that arrived was ever acquired.
      assert [%{id: _asset}] = Catalog.assets_of(comic.digital_item_id)
    end

    test "a page is addressable within the whole", %{inbox: inbox} do
      # §12.1's reader asks where a page sits in the whole, which needs the count recorded.
      comic = a_comic(inbox, 3)
      manifestation = manifestation_of(comic)

      assert %{magnitude: 3} = Addressing.get_extent(manifestation, :page)

      {:ok, selector} = DeepLink.read(:manifestation, %{"page" => "2"})
      {:ok, %{address: address}} = Catalog.create_address(manifestation, selector)

      assert {from, to} = Addressing.normalized_position(Repo.get!(Address, address.id))
      assert from < to
      assert to <= 1.0
    end

    test "an archive holding something unrenderable names it rather than guessing", %{
      inbox: inbox
    } do
      # The format is any ZIP, so the entries are the only evidence. One that no surface
      # could open is not a comic, and the finding says which entry decided it.
      prefix = unique_prefix()

      entries = [{"page-1.png", comic_page(1)}, {"setup.exe", <<0x4D, 0x5A, 0, 0>>}]
      drop!(inbox, "#{prefix}/Not A Comic.cbz", cbz(entries))
      [id] = inbox |> acquire_settled!(@t0) |> acquired()

      assert [finding] = Ingest.findings_for_acquisition(id)
      assert finding.kind == "unclassifiable"
      assert finding.detail["entries"] == ["setup.exe"]
    end

    test "an empty archive is not a comic", %{inbox: inbox} do
      prefix = unique_prefix()
      drop!(inbox, "#{prefix}/Empty.cbz", cbz([]))
      [id] = inbox |> acquire_settled!(@t0) |> acquired()

      assert [%{kind: "archive_is_empty"}] = Ingest.findings_for_acquisition(id)
    end

    test "a directory the archive declares is not a page", %{inbox: inbox} do
      # The owner's own .cbz nests its pages under `images/`, and counting that entry would
      # make a three-page comic four pages long.
      prefix = unique_prefix()

      entries = [
        {"images/", <<>>},
        {"images/page-1.png", comic_page(1)},
        {"images/page-2.png", comic_page(2)}
      ]

      [comic] = ingest!(inbox, %{"#{prefix}/Nested.cbz" => cbz(entries)})

      assert comic.media_class == :package
      assert %{magnitude: 2} = Addressing.get_extent(manifestation_of(comic), :page)
    end
  end

  describe "35. A metadata document inside a container is read as an embedded tag" do
    defp a_comic_carrying(document, pages) do
      entries =
        [{"ComicInfo.xml", document}] ++
          for n <- 1..pages, do: {"page-#{n}.png", comic_page(n)}

      prefix = unique_prefix()

      {prefix, cbz(entries)}
    end

    test "the document names the holding, as a container's own tags would", %{inbox: inbox} do
      document = comic_info(Title: "The Weight of Water", Series: "Excitebike Weekly")
      {prefix, archive} = a_comic_carrying(document, 3)

      [comic] = ingest!(inbox, %{"#{prefix}/001.cbz" => archive})

      assert comic.container_tags["title"] == "The Weight of Water"
      assert comic.container_tags["series"] == "Excitebike Weekly"

      # The name follows the document rather than the file, which is what reading it as a
      # tag means: an audio file's own `title` tag names a track the same way.
      assert names(work_of(comic)) == ["The Weight of Water"]
    end

    test "the document is no companion and makes no second holding", %{inbox: inbox} do
      document = comic_info(Title: "The Weight of Water")
      {prefix, archive} = a_comic_carrying(document, 3)

      [comic] = ingest!(inbox, %{"#{prefix}/001.cbz" => archive})

      assert comic.media_class == :package
      assert comic.companion_kind == nil
      assert Catalog.category_of(work_of(comic), Place.category_scheme()) == "comic_issue"

      # One acquisition, one digital item, one asset. A document that described the
      # container did not become a holding of its own.
      assert [%{id: _asset}] = Catalog.assets_of(comic.digital_item_id)
    end

    test "the document is not a page", %{inbox: inbox} do
      document = comic_info(Title: "The Weight of Water")
      {prefix, archive} = a_comic_carrying(document, 3)

      [comic] = ingest!(inbox, %{"#{prefix}/001.cbz" => archive})

      assert %{magnitude: 3} = Addressing.get_extent(manifestation_of(comic), :page)
    end

    test "a document the registry does not name is content", %{inbox: inbox} do
      # An XML whose root names nothing the registry knows is content, and content no
      # surface can render leaves the archive unclassified, naming the entry.
      invoice = ~s(<?xml version="1.0"?><invoice><total>3</total></invoice>)
      prefix = unique_prefix()

      entries = [{"page-1.png", comic_page(1)}, {"invoice.xml", invoice}]
      drop!(inbox, "#{prefix}/Not A Comic.cbz", cbz(entries))
      [id] = inbox |> acquire_settled!(@t0) |> acquired()

      assert [finding] = Ingest.findings_for_acquisition(id)
      assert finding.kind == "unclassifiable"
      assert finding.detail["entries"] == ["invoice.xml"]
    end

    test "a document naming a file outside itself is refused, naming it", %{inbox: inbox} do
      # §11. The document is the inbox's and may name any file. The finding says which
      # entry reached and what it reached for, and carries nothing it asked for: a
      # document that read /etc/passwd would show its first line here.
      hostile = """
      <?xml version="1.0"?>
      <!DOCTYPE ComicInfo [ <!ENTITY leak SYSTEM "file:///etc/passwd"> ]>
      <ComicInfo><Title>&leak;</Title></ComicInfo>
      """

      {prefix, archive} = a_comic_carrying(hostile, 3)
      drop!(inbox, "#{prefix}/001.cbz", archive)
      [id] = inbox |> acquire_settled!(@t0) |> acquired()

      assert [finding] = Ingest.findings_for_acquisition(id)
      assert finding.kind == "container_document_unreadable"
      assert finding.detail["entry"] == "ComicInfo.xml"
      assert finding.detail["reason"] =~ "file:///etc/passwd"
      refute finding.detail["reason"] =~ "root:"
    end
  end

  describe "38. A narration is an expression of the text, in one digital item" do
    defp a_reading(inbox, book, parts) do
      prefix = unique_prefix()

      files =
        for {part, number} <- Enum.with_index(parts, 1), into: %{} do
          {"#{prefix}/#{number}.flac",
           media!(:flac,
             tags:
               Map.merge(
                 # The tag shape a published reading actually arrives in: the author in
                 # `artist` with no `album_artist` beside it, the narrator in `narratedby`,
                 # the book in `album`, and the part as "n/total".
                 %{
                   "genre" => "Audiobook",
                   "album" => book,
                   "artist" => "Ursula K. Le Guin",
                   "narratedby" => "Rob Inglis",
                   "title" => "Chapter #{number}"
                 },
                 part
               )
           )}
        end

      ingest!(inbox, files)
    end

    defp expression_of(acquisition) do
      [expression] = Catalog.expressions_in(manifestation_of(acquisition))
      expression.id
    end

    test "the author is on the work and the narrator on the expression", %{inbox: inbox} do
      [reading] = a_reading(inbox, "A Wizard of Earthsea", [%{"track" => "1"}])

      # The work is the text, named by the book rather than by the chapter the file holds.
      assert names(work_of(reading)) == ["A Wizard of Earthsea"]
      assert Catalog.category_of(work_of(reading), Place.category_scheme()) == "audiobook"

      assert [%{role: :author, name: "Ursula K. Le Guin"}] =
               Credits.credits_of(work_of(reading))

      assert [%{role: :narrator, name: "Rob Inglis"}] =
               Credits.credits_of(expression_of(reading))
    end

    test "the narrator is credited on the reading and not on the text", %{inbox: inbox} do
      # §6.9. What the narrator made is that rendering, not the text, so the credit names
      # the expression and the narrator is no creator of the work.
      [reading] = a_reading(inbox, "A Wizard of Earthsea", [%{"track" => "1"}])

      [narrator] = Credits.credits_of(expression_of(reading))

      assert narrator.work_id == nil
      assert narrator.expression_id == expression_of(reading)
      refute narrator.agent_id in Catalog.creators_of(work_of(reading))
    end

    test "it is not a release of tracks", %{inbox: inbox} do
      [reading] = a_reading(inbox, "A Wizard of Earthsea", [%{"track" => "1"}])

      # Nothing was released as a track, so there is no release, no medium above the
      # reading, and no release key grouping one.
      assert Catalog.wholes_of(manifestation_of(reading)) == []
      assert Repo.all(ReleaseKey) == []
    end

    test "several files are one digital item carrying a part sequence", %{inbox: inbox} do
      [first, second] =
        a_reading(inbox, "A Wizard of Earthsea", [%{"track" => "1/2"}, %{"track" => "2/2"}])

      assert first.digital_item_id == second.digital_item_id

      assert [%{part_sequence: 1}, %{part_sequence: 2}] =
               first.digital_item_id
               |> Catalog.assets_of()
               |> Enum.sort_by(& &1.part_sequence)
    end

    test "a part stating no number follows those that do", %{inbox: inbox} do
      [_first, _second] = a_reading(inbox, "A Wizard of Earthsea", [%{"track" => "1/2"}, %{}])

      [reading] = Repo.all(NarrationKey)

      assert [1, 2] =
               reading.narration_digital_item_id
               |> Catalog.assets_of()
               |> Enum.map(& &1.part_sequence)
               |> Enum.sort()
    end

    test "the reading's extent is the whole reading, not one part", %{inbox: inbox} do
      [first, second] =
        a_reading(inbox, "A Wizard of Earthsea", [%{"track" => "1/2"}, %{"track" => "2/2"}])

      whole = Addressing.get_extent(manifestation_of(first), :millisecond)
      one_part = Streams.duration_ms(first.probe)

      assert whole.magnitude == one_part + Streams.duration_ms(second.probe)
      assert whole.magnitude > one_part
    end

    test "each part keeps its own probe", %{inbox: inbox} do
      # A derivation is current per tool and input, and each part is its own input, so
      # placing the second does not supersede what was read from the first.
      [first, second] =
        a_reading(inbox, "A Wizard of Earthsea", [%{"track" => "1/2"}, %{"track" => "2/2"}])

      for part <- [first, second] do
        assert [%{body_type: "probe"}] =
                 part.id |> Annotations.current_on() |> Enum.filter(&(&1.body_type == "probe"))
      end
    end
  end

  describe "§6.9. A reading's chapters are temporal addresses on it" do
    defp chapters_of(acquisition) do
      acquisition
      |> manifestation_of()
      |> Catalog.addresses_of()
      |> Enum.sort_by(& &1.start_ms)
    end

    test "each chapter the container states is a region of the reading", %{inbox: inbox} do
      prefix = unique_prefix()

      bytes =
        reading(
          chapters: [{"The Warrior", {0, 2000}}, {"The Shadow", {2000, 4000}}],
          tags: %{"track" => "1"}
        )

      [reading] = ingest!(inbox, %{"#{prefix}/book.m4b" => bytes})

      assert [first, second] = chapters_of(reading)

      assert %{selector_type: :temporal, start_ms: 0, end_ms: 2000} = first
      assert %{selector_type: :temporal, start_ms: 2000, end_ms: 4000} = second

      # The container titles them, so the addresses are named by it.
      assert names(first.id) == ["The Warrior"]
      assert names(second.id) == ["The Shadow"]
    end

    test "a chapter is no holding of its own", %{inbox: inbox} do
      # A chapter is a region of the reading, so nothing is catalogued for it: one digital
      # item, one asset, and no work or manifestation per chapter.
      prefix = unique_prefix()
      bytes = reading(chapters: [{"The Warrior", {0, 2000}}, {"The Shadow", {2000, 4000}}])

      [reading] = ingest!(inbox, %{"#{prefix}/book.m4b" => bytes})

      assert [_first, _second] = chapters_of(reading)
      assert [%{id: _asset}] = Catalog.assets_of(reading.digital_item_id)
      assert [_expression] = Catalog.expressions_in(manifestation_of(reading))
    end

    test "a chapter in a later part is offset past the parts before it", %{inbox: inbox} do
      # A container numbers its own chapters from nought, and the address is against the
      # whole reading, so part two's first chapter is not at the start of the reading.
      prefix = unique_prefix()

      [first, _second] =
        ingest!(inbox, %{
          "#{prefix}/01.m4b" => reading(chapters: [{"One", {0, 6000}}], tags: %{"track" => "1"}),
          "#{prefix}/02.m4b" => reading(chapters: [{"Two", {0, 6000}}], tags: %{"track" => "2"})
        })

      assert [one, two] = chapters_of(first)

      assert names(one.id) == ["One"]
      assert one.start_ms == 0

      assert names(two.id) == ["Two"]
      assert two.start_ms > 0
      assert two.start_ms == Streams.duration_ms(first.probe)
    end

    test "a container stating no chapters produces none", %{inbox: inbox} do
      prefix = unique_prefix()

      [reading] = ingest!(inbox, %{"#{prefix}/book.m4b" => reading(chapters: nil)})

      assert chapters_of(reading) == []
    end
  end

  describe "39. A comic issue is a work positioned within its series at manifestation level" do
    defp an_issue(inbox, series, number) do
      document = comic_info(Series: series, Number: number, Title: "Part #{number}")

      entries =
        [{"ComicInfo.xml", document}] ++
          for n <- 1..2, do: {"page-#{n}.png", comic_page(n)}

      prefix = unique_prefix()

      [issue] = ingest!(inbox, %{"#{prefix}/#{series} #{number}.cbz" => cbz(entries)})

      issue
    end

    defp series_of(issue) do
      [%{inspiration_id: serial}] = Catalog.inspirations_of(work_of(issue))
      serial
    end

    defp serial_manifestation(issue) do
      [expression] = Catalog.expressions_of(series_of(issue))
      [manifestation] = Catalog.manifestations_of(expression.id)
      manifestation.id
    end

    test "the issue is its own work, connected to the series by inspiration", %{inbox: inbox} do
      issue = an_issue(inbox, "Excitebike Weekly", 7)
      series = series_of(issue)

      refute series == work_of(issue)
      assert Catalog.category_of(work_of(issue), Place.category_scheme()) == "comic_issue"
      assert Catalog.category_of(series, Place.category_scheme()) == "comic_series"
      assert names(series) == ["Excitebike Weekly"]
    end

    test "where it sits in the series is carried between manifestations", %{inbox: inbox} do
      issue = an_issue(inbox, "Excitebike Weekly", 7)

      assert [%{part_id: part, position: 7}] = Catalog.parts_of(serial_manifestation(issue))
      assert part == manifestation_of(issue)
    end

    test "the series work has no part, which is the whole of the criterion", %{inbox: inbox} do
      # spec-01 §5.4. A series does not contain its issues. Were this a whole-part
      # relation, "issue 7" would be a property of the issue's work rather than an
      # arrangement fact about the series' manifestation.
      issue = an_issue(inbox, "Excitebike Weekly", 7)

      assert Catalog.work_parts_of(series_of(issue)) == []
    end

    test "two issues of one series find one series", %{inbox: inbox} do
      first = an_issue(inbox, "Excitebike Weekly", 7)
      second = an_issue(inbox, "Excitebike Weekly", 8)

      assert series_of(first) == series_of(second)
      assert [%{position: 7}, %{position: 8}] = Catalog.parts_of(serial_manifestation(first))
    end

    test "an issue whose number the series holds is a finding", %{inbox: inbox} do
      an_issue(inbox, "Excitebike Weekly", 7)

      document = comic_info(Series: "Excitebike Weekly", Number: 7)
      prefix = unique_prefix()
      entries = [{"ComicInfo.xml", document}, {"page-1.png", comic_page(1)}]
      drop!(inbox, "#{prefix}/again.cbz", cbz(entries))
      [id] = inbox |> acquire_settled!(@t0) |> acquired()
      Place.place_due(inbox)

      assert [%{kind: "position_taken", detail: %{"position" => 7}}] =
               Ingest.findings_for_acquisition(id)
    end

    test "a comic naming no series is placed on its own", %{inbox: inbox} do
      # Every comic the household holds carries no metadata document at all, so this is
      # the ordinary case rather than the exception.
      prefix = unique_prefix()
      entries = for n <- 1..2, do: {"page-#{n}.png", comic_page(n)}

      [issue] = ingest!(inbox, %{"#{prefix}/Unnamed 001.cbz" => cbz(entries)})

      assert Catalog.inspirations_of(work_of(issue)) == []
      assert Catalog.wholes_of(manifestation_of(issue)) == []
    end

    test "a podcast episode sits in its show the same way", %{inbox: inbox} do
      prefix = unique_prefix()

      episode = fn number ->
        media!(:flac,
          tags: %{
            "genre" => "Podcast",
            "album" => "Ologies",
            "artist" => "Alie Ward",
            "track" => "#{number}",
            "title" => "Episode #{number}"
          }
        )
      end

      [first, second] =
        ingest!(inbox, %{
          "#{prefix}/01.flac" => episode.(1),
          "#{prefix}/02.flac" => episode.(2)
        })

      show = series_of(first)

      assert Catalog.category_of(work_of(first), Place.category_scheme()) == "podcast_episode"
      assert Catalog.category_of(show, Place.category_scheme()) == "podcast"
      assert show == series_of(second)
      assert names(show) == ["Ologies"]

      # An episode is a work of its own, not a track: nothing was released as a track, so
      # there is no release above it, only the show's manifestation.
      assert [%{position: 1}, %{position: 2}] = Catalog.parts_of(serial_manifestation(first))
      assert Repo.all(ReleaseKey) == []

      # The host is still credited, as the artist of the episode's own work.
      assert [%{role: :artist, name: "Alie Ward"}] = Credits.credits_of(work_of(first))
    end

    test "the database refuses a whole-part relation between the two", %{inbox: inbox} do
      issue = an_issue(inbox, "Excitebike Weekly", 7)
      series = series_of(issue)

      assert_raise Postgrex.Error, ~r/their structure is at manifestation level/, fn ->
        Actor.as(Principals.system!().id, fn ->
          Catalog.add_work_part(series, work_of(issue))
        end)
      end
    end
  end

  describe "40. Two dumps of one game are each placed as a work of their own" do
    test "nothing in the bytes groups two dumps, so each is its own work", %{inbox: inbox} do
      prefix = unique_prefix()

      [european, american] =
        ingest!(inbox, %{
          "#{prefix}/Excitebike (E) [!].nes" => ines_rom(<<0xA5>>),
          "#{prefix}/Excitebike (U) [!].nes" => ines_rom(<<0x5A>>)
        })

      for dump <- [european, american] do
        assert dump.media_class == :software
        assert Catalog.category_of(work_of(dump), Place.category_scheme()) == "video_game"
      end

      refute work_of(european) == work_of(american)
    end

    test "no signal raises them as a candidate, because their bytes differ", %{inbox: inbox} do
      # The criterion's "nothing in the bytes groups them" is this: detection raises a pair
      # by identical bytes or a shared external identifier, and two dumps of one game share
      # neither. A member proposes the pair or nothing does.
      prefix = unique_prefix()

      ingest!(inbox, %{
        "#{prefix}/Excitebike (E) [!].nes" => ines_rom(<<0xA5>>),
        "#{prefix}/Excitebike (U) [!].nes" => ines_rom(<<0x5A>>)
      })

      assert Dedup.detect() == 0
    end

    test "a same work decision leaves them as two expressions of one work", %{
      inbox: inbox,
      actor: actor
    } do
      prefix = unique_prefix()

      [european, american] =
        ingest!(inbox, %{
          "#{prefix}/Excitebike (E) [!].nes" => ines_rom(<<0xA5>>),
          "#{prefix}/Excitebike (U) [!].nes" => ines_rom(<<0x5A>>)
        })

      {:ok, candidate} =
        Dedup.propose(manifestation_of(european), manifestation_of(american), actor.id)

      {:ok, _decided} = Dedup.decide(candidate.id, :same_work, actor.id)

      kept = work_of(european)

      assert work_of(american) == kept

      # Two expressions, not one: §8.3's same work says the two realize one creation and
      # says nothing about the realizations being one.
      assert [_one, _other] = Catalog.expressions_of(kept)
    end
  end

  describe "[spec-01] §6.5. What the bytes say a work is" do
    test "a moving image's shape reaches its expression and its work", %{inbox: inbox} do
      # The ratio is the one the presentation layer reserves a box with, so a shape recorded
      # on an expression and a shape a surface draws to are the same number.
      [film] = ingest!(inbox, %{"#{unique_prefix()}/birthday.mkv" => media!(:ffv1)})
      manifestation = manifestation_of(film)
      %{^manifestation => geometry} = Geometry.for_res([manifestation])

      embodiment = Repo.one!(from e in Embodiment, where: e.manifestation_id == ^manifestation)

      assert Repo.get!(Expression, embodiment.expression_id).significant_attributes == %{
               "aspect_ratio" => geometry.aspect_ratio
             }

      assert Repo.get!(Work, work_of(film)).representative_attributes == %{
               "aspect_ratio" => geometry.aspect_ratio
             }
    end

    test "a photograph's turn is read from its own bytes", %{inbox: inbox} do
      [photo] = ingest!(inbox, %{"#{unique_prefix()}/IMG_0001.jpg" => oriented_jpeg(6)})

      assert Repo.get!(Work, work_of(photo)).representative_attributes == %{"orientation" => 6}
    end

    test "a recording derives nothing, because a key is not in the bytes", %{inbox: inbox} do
      # §6.5's musical attributes are a key and a medium of performance, and neither is
      # readable from a container. The work carries none rather than a guess at them.
      [track] = ingest!(inbox, %{"#{unique_prefix()}/01 So What.flac" => media!(:flac)})

      assert Repo.get!(Work, work_of(track)).representative_attributes == %{}
    end
  end

  describe "8. A directory's media are placed only once everything in it is settled and identified" do
    test "a file still arriving holds back the directory's placement", %{inbox: inbox} do
      drop!(inbox, "Kind of Blue/01 So What.flac", media!(:flac, tags: album("Kind of Blue")))
      acquire_settled!(inbox, @t0)
      drop!(inbox, "Kind of Blue/02 Freddie Freeloader.flac", media!(:flac, frequency: 500))

      assert Place.place_due(inbox) == []

      acquire_settled!(inbox, DateTime.add(@t0, 3_600))

      assert [{_, :placed}, {_, :placed}] = Place.place_due(inbox)
    end

    test "an acquisition not yet identified holds it back too", %{inbox: inbox} do
      drop!(inbox, "Kind of Blue/01 So What.flac", media!(:flac))
      [id] = inbox |> acquire_settled!(@t0) |> acquired()
      stored = stored_but_unidentified!("Kind of Blue/cover.jpg", media!(:jpeg))

      assert Place.place_due(inbox) == []

      stored |> Ingest.Acquisition.identified_changeset(identified_image()) |> Repo.update!()

      assert {id, :placed} in Place.place_due(inbox)
    end

    test "a file whose identification failed does not hold the directory back",
         %{inbox: inbox} do
      drop!(inbox, "Kind of Blue/01 So What.flac", media!(:flac))
      drop!(inbox, "Kind of Blue/corrupt.flac", undecodable(700))
      acquire_settled!(inbox, @t0)

      assert [{_, :placed}] = Place.place_due(inbox)
    end
  end

  describe "7 and 9. A companion is placed as itself and linked to what it describes" do
    test "cover art links to the release, whichever is placed first", %{inbox: inbox} do
      files = %{
        "Kind of Blue/cover.jpg" => media!(:jpeg),
        "Kind of Blue/01 So What.flac" => media!(:flac, tags: album("Kind of Blue", 1)),
        "Kind of Blue/02 Freddie Freeloader.flac" =>
          media!(:flac, frequency: 500, tags: album("Kind of Blue", 2))
      }

      for {path, bytes} <- files, do: drop!(inbox, path, bytes)
      acquire_settled!(inbox, @t0)

      [cover | tracks] =
        Enum.map(
          ["Kind of Blue/cover.jpg" | Enum.sort(Map.keys(files) -- ["Kind of Blue/cover.jpg"])],
          &hd(Ingest.acquisitions_from(&1))
        )

      :placed = Place.place(cover)
      Enum.each(tracks, &(:placed = Place.place(&1)))

      cover = Ingest.get_acquisition!(cover.id)
      [release] = Catalog.associated(manifestation_of(cover), "cover-art-of")

      assert release == release_of(Ingest.get_acquisition!(hd(tracks).id))
      assert Catalog.category_of(work_of(cover), Place.category_scheme()) == "cover_art"
    end

    test "lyrics link to the track sharing their base name", %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "Kind of Blue/01 So What.flac" => media!(:flac, tags: album("Kind of Blue", 1)),
          "Kind of Blue/01 So What.lrc" => "[00:01.00]So what\n",
          "Kind of Blue/02 Freddie Freeloader.flac" =>
            media!(:flac, frequency: 500, tags: album("Kind of Blue", 2))
        })

      lyrics = Enum.find(placed, &(&1.companion_kind == "lyrics"))
      so_what = Enum.find(placed, &(&1.inbox_path == "Kind of Blue/01 So What.flac"))

      assert [manifestation_of(so_what)] ==
               Catalog.associated(manifestation_of(lyrics), "lyrics-of")
    end

    test "a metadata sidecar describes the file it is named after, and is no release",
         %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "Aladdin (1992)/Aladdin.1992.BluRay.mkv" => media!(:ffv1),
          "Aladdin (1992)/Aladdin.1992.BluRay.xml" =>
            ~s(<?xml version="1.0" encoding="UTF-8"?>\n<movie><title>Aladdin</title></movie>\n),
          "Aladdin (1992)/.plexmatch" => "tmdbid: 812\n",
          "Aladdin (1992)/Aladdin.1992.BluRay.metathumb" => media!(:jpeg),
          "Aladdin (1992)/folder.png" => media!(:png)
        })

      film = Enum.find(placed, &(&1.media_class == :video))
      sidecar = Enum.find(placed, &(Path.extname(&1.inbox_path) == ".xml"))
      match = Enum.find(placed, &(Path.basename(&1.inbox_path) == ".plexmatch"))
      cover = Enum.find(placed, &(Path.basename(&1.inbox_path) == "folder.png"))
      thumbnail = Enum.find(placed, &(Path.extname(&1.inbox_path) == ".metathumb"))

      for companion <- [sidecar, match] do
        assert companion.state == :placed,
               "#{companion.inbox_path} is #{companion.state}: " <>
                 inspect(
                   Enum.map(
                     Ingest.findings_for_acquisition(companion.id),
                     &{&1.stage, &1.kind, &1.detail}
                   )
                 )

        assert companion.media_class == :companion
        assert companion.companion_kind == "metadata"
        assert Catalog.category_of(work_of(companion), Place.category_scheme()) == "metadata"
      end

      # Named after the film, it describes the film; named after nothing, the
      # directory's one release, which for a film is the film itself.
      assert Catalog.associated(manifestation_of(sidecar), "metadata-of") ==
               [manifestation_of(film)]

      assert Catalog.associated(manifestation_of(match), "metadata-of") ==
               [manifestation_of(film)]

      # A thumbnail written beside the film is artwork, whatever its extension
      # says, and the sidecars are no longer releases of their own, so both
      # pieces of artwork have one release to describe.
      assert thumbnail.companion_kind == "cover_art"

      for artwork <- [cover, thumbnail] do
        assert Catalog.associated(manifestation_of(artwork), "cover-art-of") ==
                 [manifestation_of(film)]
      end

      assert Enum.flat_map([film, cover, thumbnail], &Ingest.findings_for_acquisition(&1.id)) ==
               []
    end

    test "a sidecar named after a track describes the track, not the release",
         %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "Kind of Blue/01 So What.flac" => media!(:flac, tags: album("Kind of Blue", 1)),
          "Kind of Blue/01 So What.xml" =>
            ~s(<?xml version="1.0" encoding="UTF-8"?>\n<details><title>So What</title></details>\n),
          "Kind of Blue/02 Freddie Freeloader.flac" =>
            media!(:flac, frequency: 500, tags: album("Kind of Blue", 2))
        })

      sidecar = Enum.find(placed, &(&1.companion_kind == "metadata"))
      so_what = Enum.find(placed, &(&1.inbox_path == "Kind of Blue/01 So What.flac"))

      assert Catalog.associated(manifestation_of(sidecar), "metadata-of") ==
               [manifestation_of(so_what)]

      refute manifestation_of(so_what) == release_of(so_what)
    end

    test "an .nfo of markup and an .nfo of notes are different companions", %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "Kind of Blue/01 So What.flac" => media!(:flac, tags: album("Kind of Blue", 1)),
          "Kind of Blue/album.nfo" => """
          <album>
            <title>Kind of Blue</title>
            <musicbrainzalbumid>1fd4d3d0-eb4a-3fc5-8ad1-d2eb2b1b0e0a</musicbrainzalbumid>
            <label>Columbia</label>
          </album>
          """,
          "Kind of Blue/release.nfo" => """
           :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
           :  Kind.Of.Blue.1959.Remastered.24bit.FLAC-GROUP                :
           :  Source ..... CD            Tracks ..... 5                    :
           :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
          """
        })

      sidecar = Enum.find(placed, &(&1.inbox_path == "Kind of Blue/album.nfo"))
      notes = Enum.find(placed, &(&1.inbox_path == "Kind of Blue/release.nfo"))
      track = Enum.find(placed, &(&1.media_class == :audio))

      assert sidecar.companion_kind == "metadata"
      assert notes.companion_kind == "description"

      assert Catalog.associated(manifestation_of(sidecar), "metadata-of") == [release_of(track)]
      assert Catalog.associated(manifestation_of(notes), "description-of") == [release_of(track)]
    end

    test "a subtitle carrying marks the film does not describes the film", %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "Tarkovsky/Stalker.1979.mkv" => media!(:film),
          "Tarkovsky/Stalker.1979.Extras.mkv" => media!(:film, audio: [{"rus", "flac", nil}]),
          "Tarkovsky/Stalker.1979.Extras.en.forced.srt" =>
            "1\n00:00:01,000 --> 00:00:02,000\nWhat do you want?\n\n" <>
              "2\n00:00:03,000 --> 00:00:04,000\nTo be left alone.\n\n"
        })

      subtitle = Enum.find(placed, &(&1.companion_kind == "subtitles"))
      stalker = Enum.find(placed, &(&1.inbox_path == "Tarkovsky/Stalker.1979.Extras.mkv"))

      assert subtitle.media_class == :companion
      assert Catalog.category_of(work_of(subtitle), Place.category_scheme()) == "subtitles"

      assert Catalog.associated(manifestation_of(subtitle), "subtitles-of") ==
               [manifestation_of(stalker)]

      assert Ingest.findings_for_acquisition(subtitle.id) == []
    end

    test "a subtitle whose name merely begins with a film's is not that film's",
         %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "Kurosawa/Ran.mkv" => media!(:film),
          "Kurosawa/Rashomon.mkv" => media!(:film, audio: [{"jpn", "flac", nil}]),
          "Kurosawa/Random subtitles.en.srt" =>
            "1\n00:00:01,000 --> 00:00:02,000\nFor some other film.\n\n"
        })

      stray = Enum.find(placed, &(&1.companion_kind == "subtitles"))

      assert Catalog.associated(manifestation_of(stray), "subtitles-of") == []

      assert [%{kind: "companion_describes_several_releases"}] =
               Ingest.findings_for_acquisition(stray.id)
    end

    test "a directory that produced two releases leaves its cover unlinked, as a finding",
         %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "mixed/cover.jpg" => media!(:jpeg),
          "mixed/so-what.flac" => media!(:flac, tags: album("Kind of Blue", 1)),
          "mixed/pharaoh.flac" => media!(:flac, frequency: 500, tags: album("Bitches Brew", 1))
        })

      cover = Enum.find(placed, &(&1.media_class == :companion))

      assert Catalog.associated(manifestation_of(cover), "cover-art-of") == []

      assert [%{stage: :place, kind: "companion_describes_several_releases"}] =
               Ingest.findings_for_acquisition(cover.id)
    end
  end

  describe "10. Removing a companion does not remove the described holding's master" do
    test "recycling the cover leaves the track's assets live", %{inbox: inbox, actor: actor} do
      placed =
        ingest!(inbox, %{
          "Kind of Blue/cover.jpg" => media!(:jpeg),
          "Kind of Blue/01 So What.flac" => media!(:flac, tags: album("Kind of Blue", 1))
        })

      cover = Enum.find(placed, &(&1.media_class == :companion))
      track = Enum.find(placed, &(&1.media_class == :audio))

      {:ok, recycling} = Lifecycle.recycle(work_of(cover), actor.id)

      refute track.id in Lifecycle.contents(recycling.id)
      assert {:live, _} = Lifecycle.state(track.id)
    end
  end

  describe "11. Placement writes a holding in one transaction; no asset without its digital item" do
    test "bytes changed after identification leave nothing written", %{inbox: inbox} do
      drop!(inbox, "holiday/IMG_0001.png", media!(:png))
      [id] = inbox |> acquire_settled!(@t0) |> acquired()
      acquisition = Ingest.get_acquisition!(id)
      :ok = Storage.put(acquisition.location, StorageFixtures.png("not what was identified"))
      works_before = Repo.aggregate(Work, :count)

      assert_raise RuntimeError, ~r/changed after they were identified/, fn ->
        Place.place(acquisition)
      end

      assert Repo.aggregate(Work, :count) == works_before
      assert Repo.get(Asset, id) == nil
      assert Repo.all(from d in DigitalItem, where: d.id == ^id) == []
      assert %Acquisition{state: :identified} = Ingest.get_acquisition!(id)
    end

    test "one holding that crashes is a finding, and the pass places the rest", %{inbox: inbox} do
      drop!(inbox, "holiday/IMG_0001.png", media!(:png))
      drop!(inbox, "holiday/IMG_0002.jpg", media!(:jpeg))
      [broken_id, sound_id] = inbox |> acquire_settled!(@t0) |> acquired() |> Enum.sort()
      broken = Ingest.get_acquisition!(broken_id)
      :ok = Storage.put(broken.location, StorageFixtures.png("not what was identified"))

      assert [{^broken_id, {:crashed, message}}, {^sound_id, :placed}] = Place.place_due(inbox)
      assert message =~ "changed after they were identified"

      assert [%{stage: :place, kind: "crashed", permanent: false}] =
               Ingest.findings_for_acquisition(broken_id)

      assert Place.place_due(inbox) == []
    end

    test "every placed asset realizes a digital item carrying a manifestation", %{inbox: inbox} do
      placed =
        ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png), "notes.txt" => "a note\n"})

      for acquisition <- placed do
        asset = Repo.get!(Asset, acquisition.id)
        digital_item = Repo.get!(DigitalItem, asset.digital_item_id)
        assert digital_item.id == acquisition.digital_item_id
        assert Catalog.expressions_in(digital_item.manifestation_id) != []
      end
    end
  end

  describe "12. Names and categories are automatic; a correction outranks them and survives" do
    test "placement's names and category are automatic", %{inbox: inbox} do
      [photo] = ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png)})
      work = work_of(photo)

      assert [%Nomen{provenance: :automatic, nomen_string: "IMG_0001"}] = Catalog.nomens_for(work)
      assert [%{provenance: :automatic, value: "photograph"}] = Catalog.categories_of(work)
    end

    test "a member's correction wins, and a later track adds nothing to the release",
         %{inbox: inbox} do
      [so_what] =
        ingest!(inbox, %{
          "Kind of Blue/01 So What.flac" => media!(:flac, tags: album("Kind of Blue", 1))
        })

      release_work = work_of_release(so_what)
      {:ok, _} = Catalog.create_nomen(%{res_id: release_work, nomen_string: "KoB (mono)"})
      {:ok, _} = Catalog.categorize(release_work, Place.category_scheme(), "compilation", :local)

      ingest!(
        inbox,
        %{
          "Kind of Blue/02 Freddie Freeloader.flac" =>
            media!(:flac, frequency: 500, tags: album("Kind of Blue", 2))
        },
        DateTime.add(@t0, 3_600)
      )

      Place.place_due(inbox)

      assert Enum.sort(Enum.map(Catalog.nomens_for(release_work), & &1.nomen_string)) ==
               ["Kind of Blue", "KoB (mono)"]

      assert Catalog.category_of(release_work, Place.category_scheme()) == "compilation"
      assert [_, _] = Catalog.categories_of(release_work)
    end
  end

  describe "13. Tracks are positioned within a medium, positioned within the release" do
    test "two discs, each with its tracks in order, and no arrangement on the aggregation",
         %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "Box/1-01.flac" => media!(:flac, tags: album("Box", 1, disc: "1/2")),
          "Box/1-02.flac" => media!(:flac, frequency: 500, tags: album("Box", 2, disc: "1/2")),
          "Box/2-01.flac" => media!(:flac, frequency: 700, tags: album("Box", 1, disc: "2/2"))
        })

      release = release_of(hd(placed))

      assert [%{position: 1, part_id: disc_one}, %{position: 2, part_id: disc_two}] =
               Catalog.parts_of(release)

      track = &manifestation_of(Enum.find(placed, fn a -> a.inbox_path == &1 end))

      assert [%{position: 1, part_id: one}, %{position: 2, part_id: two}] =
               Catalog.parts_of(disc_one)

      assert {one, two} == {track.("Box/1-01.flac"), track.("Box/1-02.flac")}
      assert [%{position: 1, part_id: three}] = Catalog.parts_of(disc_two)
      assert three == track.("Box/2-01.flac")

      album_expressions = Enum.map(Catalog.expressions_in(release), & &1.id)

      assert [nil, nil, nil] =
               Repo.all(
                 from a in Aggregation,
                   where: a.aggregating_expression_id in ^album_expressions,
                   select: a.arrangement
               )
    end
  end

  describe "14. Grouping is independent of order; a missing field equals only a missing field" do
    test "every order of the same files gives the same releases", %{inbox: inbox} do
      partitions =
        for {order, run} <- Enum.with_index(permutations(["a", "b", "c"])) do
          album = "Kind of Blue #{run}"

          files = %{
            "a" => media!(:flac, frequency: 300 + run, tags: album(album, 1, date: "1959")),
            "b" => media!(:flac, frequency: 400 + run, tags: album(album, 2)),
            "c" => media!(:flac, frequency: 500 + run, tags: album(album, 3, date: "1959"))
          }

          dir = "run-#{run}"
          for {name, bytes} <- files, do: drop!(inbox, "#{dir}/#{name}.flac", bytes)
          acquire_settled!(inbox, DateTime.add(@t0, run * 3_600))

          for name <- order do
            :placed = Place.place(hd(Ingest.acquisitions_from("#{dir}/#{name}.flac")))
          end

          ["a", "b", "c"]
          |> Enum.group_by(&release_of(hd(Ingest.acquisitions_from("#{dir}/#{&1}.flac"))))
          |> Map.values()
          |> Enum.sort()
        end

      assert [[["a", "c"], ["b"]]] = Enum.uniq(partitions)
    end
  end

  describe "15. Placements with one grouping key make one release" do
    test "a track finds the release another placement committed under its key",
         %{inbox: inbox} do
      [so_what] =
        ingest!(inbox, %{"KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1))})

      [key] = Repo.all(ReleaseKey)

      assert key.release_manifestation_id == release_of(so_what)

      [freddie] =
        ingest!(
          inbox,
          %{"KoB/02.flac" => media!(:flac, frequency: 500, tags: album("Kind of Blue", 2))},
          DateTime.add(@t0, 3_600)
        )

      assert release_of(freddie) == release_of(so_what)
      assert [_] = Repo.all(ReleaseKey)
    end

    test "a key whose release was deleted gathers a new release", %{inbox: inbox, actor: actor} do
      [so_what] =
        ingest!(inbox, %{"KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1))})

      old_release = release_of(so_what)
      {:ok, _} = Lifecycle.recycle(old_release, actor.id)

      [freddie] =
        ingest!(
          inbox,
          %{"KoB/02.flac" => media!(:flac, frequency: 500, tags: album("Kind of Blue", 2))},
          DateTime.add(@t0, 3_600)
        )

      refute release_of(freddie) == old_release
      assert [%{release_manifestation_id: current}] = Repo.all(ReleaseKey)
      assert current == release_of(freddie)
    end

    test "the key is unique in the database" do
      now = DateTime.utc_now()
      row = %{key: "tags:[\"Kind of Blue\"]", inserted_at: now, updated_at: now}
      {1, _} = Repo.insert_all(ReleaseKey, [row])

      assert_raise Postgrex.Error, ~r/release_keys_pkey/, fn ->
        Repo.insert_all(ReleaseKey, [row])
      end
    end
  end

  describe "spec-01 §6.3. Placement relates a holding to when its edition was issued" do
    test "the date the container states becomes a time-span the manifestation relates to",
         %{inbox: inbox} do
      [track] =
        ingest!(inbox, %{
          "KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1, date: "1959-08-17"))
        })

      assert [time_span] = issued(manifestation_of(track))

      assert Repo.get!(Res, time_span).kind == :time_span
      assert names(time_span) == ["1959-08-17"]
    end

    test "it hangs off the manifestation, because the date is the edition's",
         %{inbox: inbox} do
      # A reissue and a first pressing are one work and two dates, so the work is not
      # what carries one.
      [track] =
        ingest!(inbox, %{
          "KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1, date: "1959"))
        })

      assert issued(manifestation_of(track)) != []
      assert issued(work_of(track)) == []
    end

    test "two holdings stating one date relate to one time-span", %{inbox: inbox} do
      # The point of the key: a time-span is a res and its name with no table of its
      # own, so without it each holding would carry a span nothing else shares and
      # nothing could be grouped by date.
      [first, second] =
        ingest!(inbox, %{
          "KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1, date: "1959")),
          "Milestones/01.flac" =>
            media!(:flac, frequency: 500, tags: album("Milestones", 1, date: "1959"))
        })

      assert issued(manifestation_of(first)) == issued(manifestation_of(second))
      assert [_one_span] = Repo.all(TimeSpanKey)
    end

    test "two dates stated to different precisions are two time-spans", %{inbox: inbox} do
      # `1959` and `1959-08` are not the same statement, and collapsing them would
      # either invent a month or discard one.
      [coarse, fine] =
        ingest!(inbox, %{
          "A/01.flac" => media!(:flac, tags: album("A", 1, date: "1959")),
          "B/01.flac" => media!(:flac, frequency: 500, tags: album("B", 1, date: "1959-08"))
        })

      refute issued(manifestation_of(coarse)) == issued(manifestation_of(fine))
      assert Repo.all(TimeSpanKey) |> Enum.map(& &1.key) |> Enum.sort() == ["1959", "1959-08"]
    end

    test "a reading in several parts is dated once, not once per part", %{inbox: inbox} do
      # Every part of a reading is an asset of one digital item under one manifestation,
      # so each part states the same date about the same res. Writing the relation again
      # for the second part is refused by the triple's own index, and placement would
      # have recorded a crash and left the part unplaced.
      placed =
        ingest!(inbox, %{
          "Earthsea/01.m4b" => reading(book: "Earthsea", tags: %{"date" => "1968"}),
          "Earthsea/02.m4b" => reading(book: "Earthsea", duration: 7, tags: %{"date" => "1968"})
        })

      assert [first, second] = placed
      assert first.digital_item_id == second.digital_item_id

      reading_manifestation = Repo.get!(DigitalItem, first.digital_item_id).manifestation_id

      assert [time_span] = issued(reading_manifestation)
      assert names(time_span) == ["1968"]
    end

    test "a holding placed before anything read a date can be read afterwards",
         %{inbox: inbox} do
      [track] =
        ingest!(inbox, %{
          "KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1, date: "1959"))
        })

      # As it would stand for a holding placed before the date was read at all.
      manifestation = manifestation_of(track)
      [span] = issued(manifestation)
      Repo.delete_all(from a in Association, where: a.object_id == ^span)

      assert issued(manifestation) == []
      assert Place.record_date(track) == :recorded
      assert [^span] = issued(manifestation)
    end

    test "reading a holding that already carries its date records nothing new",
         %{inbox: inbox} do
      [track] =
        ingest!(inbox, %{
          "KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1, date: "1959"))
        })

      before = issued(manifestation_of(track))

      assert Place.record_date(track) == :recorded
      assert issued(manifestation_of(track)) == before
    end

    test "a holding stating no date it can read is left alone", %{inbox: inbox} do
      [track] =
        ingest!(inbox, %{
          "KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1, date: "17/08/1959"))
        })

      assert Place.record_date(track) == :states_none
      assert issued(manifestation_of(track)) == []
    end

    test "a container stating no date relates to nothing", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1))})

      assert issued(manifestation_of(track)) == []
      assert Repo.all(TimeSpanKey) == []
    end

    test "a date in a form whose field order it does not fix relates to nothing",
         %{inbox: inbox} do
      [track] =
        ingest!(inbox, %{
          "KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1, date: "17/08/1959"))
        })

      assert issued(manifestation_of(track)) == []
    end

    test "the file's own timestamp is never the date", %{inbox: inbox} do
      # A copy resets it, an extraction sets it to the extraction and a restore to the
      # restore, so it says when the bytes were last written and nothing else. These
      # bytes are written now and state 1959; nothing may record this year.
      [track] =
        ingest!(inbox, %{
          "KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1, date: "1959"))
        })

      assert [time_span] = issued(manifestation_of(track))
      assert names(time_span) == ["1959"]

      this_year = to_string(Date.utc_today().year)
      refute Enum.any?(Repo.all(TimeSpanKey), &String.starts_with?(&1.key, this_year))
    end

    test "a span whose res was recycled no longer dates anything", %{
      inbox: inbox,
      actor: actor
    } do
      [first] =
        ingest!(inbox, %{"A/01.flac" => media!(:flac, tags: album("A", 1, date: "1959"))})

      [gone] = issued(manifestation_of(first))
      {:ok, _} = Lifecycle.recycle(gone, actor.id)

      [second] =
        ingest!(
          inbox,
          %{"B/01.flac" => media!(:flac, frequency: 500, tags: album("B", 1, date: "1959"))},
          DateTime.add(@t0, 3_600)
        )

      [current] = issued(manifestation_of(second))

      refute current == gone
      assert [%{time_span_id: ^current}] = Repo.all(TimeSpanKey)
    end
  end

  defp issued(res_id),
    do: Catalog.associated(res_id, Refinements.name!("time-of-publication-or-manufacture"))

  describe "16. Contradictory evidence and a taken position are findings, never guesses" do
    test "a track carrying two release identifiers is not placed", %{inbox: inbox} do
      tags = Map.put(album("Kind of Blue", 1), "MUSICBRAINZ_ALBUMID", "mb-one;mb-two")
      drop!(inbox, "KoB/01.flac", media!(:flac, tags: tags))
      [id] = inbox |> acquire_settled!(@t0) |> acquired()

      assert [{^id, :finding}] = Place.place_due(inbox)
      assert %Acquisition{state: :identified} = Ingest.get_acquisition!(id)

      assert [
               %{
                 kind: "evidence_names_two_releases",
                 detail: %{"identifiers" => ["mb-one", "mb-two"]}
               }
             ] =
               Ingest.findings_for_acquisition(id)

      assert Place.place_due(inbox) == []
    end

    test "a second track at a taken position is not placed", %{inbox: inbox} do
      drop!(inbox, "KoB/01.flac", media!(:flac, tags: album("Kind of Blue", 1)))

      drop!(
        inbox,
        "KoB/01 again.flac",
        media!(:flac, frequency: 500, tags: album("Kind of Blue", 1))
      )

      acquire_settled!(inbox, @t0)

      assert [{_, :placed}, {second, :finding}] = Place.place_due(inbox)
      assert [%{kind: "position_taken"}] = Ingest.findings_for_acquisition(second)
    end
  end

  describe "17. A release in one file is one digital item; its tracks are temporal addresses" do
    test "the cue sheet's tracks are located within the release's file", %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "Kind of Blue/album.flac" => media!(:flac, duration: 6),
          "Kind of Blue/album.cue" => """
          TITLE "Kind of Blue"
          PERFORMER "Miles Davis"
          FILE "album.flac" WAVE
            TRACK 01 AUDIO
              TITLE "So What"
              INDEX 01 00:00:00
            TRACK 02 AUDIO
              TITLE "Freddie Freeloader"
              INDEX 00 00:02:70
              INDEX 01 00:03:00
          """
        })

      album = Enum.find(placed, &(&1.media_class == :audio))
      release = manifestation_of(album)

      assert Catalog.wholes_of(release) == []
      assert [%{position: 1, part_id: medium}] = Catalog.parts_of(release)

      assert [%{position: 1, part_id: so_what}, %{position: 2, part_id: freddie}] =
               Catalog.parts_of(medium)

      assert Repo.all(from d in DigitalItem, where: d.manifestation_id in [^so_what, ^freddie]) ==
               []

      extents =
        for track <- [so_what, freddie] do
          [address_id] = Catalog.associated(track, "extent-of")
          address = Repo.get!(Address, address_id)
          assert address.target_id == release
          {address.start_ms, address.end_ms}
        end

      assert extents == [{0, 3_000}, {3_000, 6_000}]
    end
  end

  describe "names written in either Unicode form compare equal" do
    # "Bourrée" with é as one code point, and as e with a combining accent, as
    # macOS and the Internet Archive write file names.
    @composed "Bourrée"
    @decomposed "Bourrée"

    test "a cue sheet finds its file whichever form each was written in", %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "Chopin/#{@decomposed}.flac" => media!(:flac, duration: 4),
          "Chopin/album.cue" => """
          FILE "#{@composed}.flac" WAVE
            TRACK 01 AUDIO
              INDEX 01 00:00:00
            TRACK 02 AUDIO
              INDEX 01 00:02:00
          """
        })

      album = Enum.find(placed, &(&1.media_class == :audio))

      assert [%{part_id: medium}] = Catalog.parts_of(manifestation_of(album))
      assert [_, _] = Catalog.parts_of(medium)
    end

    test "a cue sheet written decomposed finds a file named composed", %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "Chopin/#{@composed}.flac" => media!(:flac, duration: 4),
          "Chopin/album.cue" => """
          FILE "#{@decomposed}.flac" WAVE
            TRACK 01 AUDIO
              INDEX 01 00:00:00
          """
        })

      album = Enum.find(placed, &(&1.media_class == :audio))

      assert [%{part_id: medium}] = Catalog.parts_of(manifestation_of(album))
      assert [_] = Catalog.parts_of(medium)
      assert Catalog.wholes_of(manifestation_of(album)) == []
    end

    test "lyrics link to their track whichever form each was written in", %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "Chopin/#{@composed}.flac" => media!(:flac, tags: album("Chopin", 1)),
          "Chopin/#{@decomposed}.lrc" => "[00:01.00]la\n"
        })

      lyrics = Enum.find(placed, &(&1.companion_kind == "lyrics"))
      track = Enum.find(placed, &(&1.media_class == :audio))

      assert Catalog.associated(manifestation_of(lyrics), "lyrics-of") == [
               manifestation_of(track)
             ]
    end

    test "album tags from two taggers make one release", %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "a.flac" =>
            media!(:flac,
              tags: %{"album" => @composed, "album_artist" => "Chopin", "track" => "1"}
            ),
          "b.flac" =>
            media!(:flac,
              frequency: 500,
              tags: %{"album" => @decomposed, "album_artist" => "Chopin", "track" => "2"}
            )
        })

      assert [one, two] = Enum.map(placed, &release_of/1)
      assert one == two
    end
  end

  describe "18. Streams become one expression, parallel expressions, or a work of their own" do
    test "languages are parallel expressions; a commentary is a work of its own",
         %{inbox: inbox} do
      bytes =
        media!(:film,
          audio: [{"rus", "flac", nil}, {"eng", "aac", nil}, {"eng", "aac", "comment"}]
        )

      [film] = ingest!(inbox, %{"Stalker.mkv" => bytes})
      manifestation = manifestation_of(film)
      expressions = Catalog.expressions_in(manifestation)

      by_work = Enum.group_by(expressions, & &1.work_id)
      assert map_size(by_work) == 2

      [{film_work, [_, _]}, {commentary_work, [_]}] =
        Enum.sort_by(by_work, fn {_work, expressions} -> -length(expressions) end)

      # The commentary rides in the film's manifestation, so it is a track of the film in
      # the same way its second audio stream is. It keeps its own URI and reaches track
      # selection; what it is not is a second thing the household holds.
      listed = Entries.ids(%Query{mode: "everything"}, 100)

      assert film_work in listed
      refute commentary_work in listed
    end

    test "a downmix of one language is not a second expression", %{inbox: inbox} do
      bytes = media!(:film, audio: [{"rus", "flac", nil}, {"rus", "aac", nil}])

      [film] = ingest!(inbox, %{"Stalker.mkv" => bytes})

      assert [%Expression{}] = Catalog.expressions_in(manifestation_of(film))
    end
  end

  describe "19. Every content stream has a track address that survives normalization" do
    test "each content stream is addressed on the container", %{inbox: inbox} do
      [film] = ingest!(inbox, %{"Stalker.mkv" => media!(:film)})

      tracks =
        film
        |> manifestation_of()
        |> Catalog.addresses_of()
        |> Enum.filter(&(&1.selector_type == :track))

      assert Enum.sort(Enum.map(tracks, &{&1.stream_kind, &1.stream_language})) ==
               [audio: "eng", audio: "rus", video: nil]
    end

    test "reordering and re-encoding the streams names the same streams", %{inbox: inbox} do
      drop!(inbox, "original.mkv", media!(:film))
      drop!(inbox, "normalized.mkv", media!(:film_remuxed))
      acquire_settled!(inbox, @t0)

      [original, normalized] =
        for path <- ["original.mkv", "normalized.mkv"] do
          [acquisition] = Ingest.acquisitions_from(path)

          acquisition.streams
          |> Enum.filter(& &1["content"])
          |> Streams.track_selectors()
          |> Enum.sort()
        end

      assert original == normalized

      refute Enum.map(hd(Ingest.acquisitions_from("original.mkv")).streams, & &1["codec"]) ==
               Enum.map(hd(Ingest.acquisitions_from("normalized.mkv")).streams, & &1["codec"])
    end
  end

  describe "29. Two scans resolved as one expression leave one work" do
    test "the rescan's own work and expression are recycled", %{inbox: inbox, actor: actor} do
      [first, rescan] =
        ingest!(inbox, %{
          "letters/1943-04-12.png" => media!(:png),
          "letters/1943-04-12 rescan.png" => media!(:jpeg)
        })

      stray_work = work_of(rescan)
      {:ok, candidate} = Dedup.propose(first.digital_item_id, rescan.digital_item_id, actor.id)
      {:ok, _} = Dedup.decide(candidate.id, :same_expression, actor.id)

      assert {:recycled, _, _} = Lifecycle.state(stray_work)
      assert [expression] = Catalog.expressions_in(manifestation_of(first))
      assert [_, _] = Catalog.manifestations_of(expression.id)
    end
  end

  describe "30. Every catalog write ingest makes is attributed to the System principal" do
    test "placement writes nothing as anyone else", %{inbox: inbox, system: system} do
      since = DateTime.utc_now()

      ingest!(inbox, %{
        "Kind of Blue/cover.jpg" => media!(:jpeg),
        "Kind of Blue/01 So What.flac" => media!(:flac, tags: album("Kind of Blue", 1)),
        "Stalker.mkv" => media!(:film)
      })

      writers =
        Repo.all(
          from w in "catalog_writes",
            where: w.occurred_at >= ^since,
            distinct: true,
            select: type(w.principal_id, UUIDv7)
        )

      assert writers == [system.id]
    end
  end

  describe "placement is idempotent (§6.9)" do
    test "a second pass places nothing and writes nothing", %{inbox: inbox} do
      ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png)})
      writes = Repo.aggregate("catalog_writes", :count)

      assert Place.place_due(inbox) == []
      assert Repo.aggregate("catalog_writes", :count) == writes
    end
  end

  describe "a lossless holding's acquired asset is its original (spec-03 §3.3)" do
    test "the asset carries the Acquired role", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1))})

      assert Assets.role_classes_of(track.id) == [:acquired]
    end
  end

  defp ingest!(inbox, files, from \\ @t0) do
    for {path, bytes} <- files, do: drop!(inbox, path, bytes)
    ids = inbox |> acquire_settled!(from) |> acquired()
    place_all!(inbox)
    ids |> Enum.map(&Ingest.get_acquisition!/1) |> Enum.sort_by(& &1.inbox_path)
  end

  defp album(name, track \\ nil, opts \\ []) do
    %{"album" => name, "album_artist" => "Miles Davis"}
    |> put_tag("track", track && "#{track}")
    |> put_tag("date", opts[:date])
    |> put_tag("disc", opts[:disc])
  end

  defp put_tag(tags, _key, nil), do: tags
  defp put_tag(tags, key, value), do: Map.put(tags, key, value)

  defp permutations([]), do: [[]]

  defp permutations(list),
    do: for(x <- list, rest <- permutations(list -- [x]), do: [x | rest])

  defp manifestation_of(acquisition),
    do: Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id

  defp work_of(acquisition) do
    [expression | _] = Catalog.expressions_in(manifestation_of(acquisition))
    expression.work_id
  end

  defp release_of(track) do
    [%{whole_id: medium}] = Catalog.wholes_of(manifestation_of(track))
    [%{whole_id: release}] = Catalog.wholes_of(medium)
    release
  end

  defp work_of_release(track) do
    [expression] = Catalog.expressions_in(release_of(track))
    expression.work_id
  end

  defp names(res_id), do: Enum.map(Catalog.nomens_for(res_id), & &1.nomen_string)

  defp stored_but_unidentified!(inbox_path, bytes) do
    id = UUIDv7.generate()
    cleanup(id)
    location = Ingest.location_for(id)
    :ok = Storage.put(location, bytes)

    %{id: id, inbox_path: inbox_path, location: location}
    |> Acquisition.recorded_changeset()
    |> Repo.insert!()
    |> Ecto.Changeset.change(inbox_released_at: DateTime.utc_now())
    |> Repo.update!()
    |> Acquisition.stored_changeset(elem(Storage.measure(location), 1))
    |> Repo.update!()
  end

  defp identified_image do
    %{
      format: "fmt/44",
      probe: nil,
      streams: [],
      essence: :lossy,
      media_class: :companion,
      companion_kind: "cover_art",
      container_tags: %{}
    }
  end
end
