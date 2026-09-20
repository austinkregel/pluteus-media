defmodule Pluteus.Ingest.PlacementTest do
  @moduledoc """
  Placement: spec-04 §6 and the conformance criteria it carries. Each
  `describe` names its criterion.
  """

  use Pluteus.DataCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Annotations
  alias Pluteus.Assets
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Aggregation
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Work
  alias Pluteus.Dedup
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Place
  alias Pluteus.Ingest.ReleaseKey
  alias Pluteus.Ingest.Streams
  alias Pluteus.Lifecycle
  alias Pluteus.Principals
  alias Pluteus.Storage
  alias Pluteus.StorageFixtures

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup do
    system = Principals.system!()
    %{inbox: inbox!(), system: system}
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

    test "the probe's reading becomes a derived annotation on the manifestation",
         %{inbox: inbox} do
      [track] = ingest!(inbox, %{"KoB/01.flac" => media!(:flac, tags: album("Kind of Blue", 1))})
      manifestation = manifestation_of(track)

      assert [%{body_type: "probe", body: body, derivation_id: derivation_id}] =
               Annotations.current_on(manifestation)

      assert body == track.probe
      assert Annotations.current_derivation("ffprobe", manifestation).id == derivation_id
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
      drop!(inbox, "Kind of Blue/corrupt.flac", :crypto.strong_rand_bytes(700))
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

      [{_film_work, [_, _]}, {_commentary_work, [_]}] =
        Enum.sort_by(by_work, fn {_work, expressions} -> -length(expressions) end)
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
    Place.place_due(inbox)
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
      companion_kind: "cover_art"
    }
  end
end
