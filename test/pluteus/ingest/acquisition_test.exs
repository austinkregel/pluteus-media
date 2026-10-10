defmodule Pluteus.Ingest.AcquisitionTest do
  @moduledoc """
  Acquisition and identification: spec-04 §4, §5 and the conformance criteria
  they carry. Each `describe` names its criterion.
  """

  use Pluteus.DataCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog.Asset
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Identify
  alias Pluteus.PlatformEvents
  alias Pluteus.Principals
  alias Pluteus.Storage

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup do
    %{inbox: inbox!()}
  end

  describe "§4.1. Files enter through an inbox" do
    test "a relative path identifies a file deployment-wide, so there is one inbox" do
      # §4.1 gives the household one inbox, and these two keys are what the rest of
      # ingest rests on: neither names an inbox, so a path relative to one is an identity
      # across the whole deployment. A second watched directory would collide with the
      # first on both, silently for the sighting and loudly for the acquisition, so
      # adding one means re-keying both and `Pluteus.Ingest.inbox/0` says as much.
      #
      # This is also why `Place.place_due/1` is not narrowed by the inbox it is given.
      # The closing bracket is part of each match, so a key gaining a second column fails
      # here rather than passing on a prefix.
      assert index_definition("inbox_sightings_pkey") =~ "btree (inbox_path)"

      assert index_definition("acquisitions_one_in_progress_per_path_index") =~
               "btree (inbox_path)"
    end

    test "the deployment's inbox is the one the configuration names" do
      assert Ingest.inbox() ==
               :pluteus |> Application.fetch_env!(Ingest) |> Keyword.fetch!(:inbox)
    end
  end

  describe "a file arriving is announced to the household ([spec-01] §11.1, §11.2)" do
    test "the arrival names the acquisition, there being nothing catalogued yet",
         %{inbox: inbox} do
      drop!(inbox, "so-what.flac", media!(:flac))

      [id] = inbox |> acquire_settled!(@t0) |> acquired()

      assert [%{type: "acquired", res_id: nil, recorded_by: by}] =
               PlatformEvents.about_acquisition(id)

      assert by == Principals.system!().id
    end

    test "a file that never identifies was still an arrival the household saw",
         %{inbox: inbox} do
      # The case announcing at placement would have lost: nothing is catalogued, so
      # there is no res to name and no `placed` event will ever follow.
      drop!(inbox, "empty.bin", "")

      [id] = inbox |> acquire_settled!(@t0) |> acquired()

      refute Ingest.get_acquisition!(id).state == :identified
      assert [%{type: "acquired"}] = PlatformEvents.about_acquisition(id)
    end
  end

  describe "1. A file in the inbox is moved into primary storage and gains a record" do
    test "the bytes leave the inbox and lie at the record's location", %{inbox: inbox} do
      bytes = media!(:flac)
      drop!(inbox, "Kind of Blue/01 So What.flac", bytes)

      [id] = inbox |> acquire_settled!(@t0) |> acquired()

      acquisition = Ingest.get_acquisition!(id)
      assert acquisition.inbox_path == "Kind of Blue/01 So What.flac"
      assert acquisition.inbox_directory == "Kind of Blue"
      assert Storage.read(acquisition.location) == bytes
      refute File.exists?(Path.join(inbox, "Kind of Blue/01 So What.flac"))
    end

    test "the record carries what was measured from the stored bytes", %{inbox: inbox} do
      bytes = media!(:flac)
      drop!(inbox, "so-what.flac", bytes)

      [id] = inbox |> acquire_settled!(@t0) |> acquired()

      acquisition = Ingest.get_acquisition!(id)
      assert acquisition.size == byte_size(bytes)
      assert acquisition.digest == :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
      assert acquisition.state == :identified
      assert acquisition.format == "fmt/279"
      assert acquisition.media_class == :audio
    end
  end

  describe "2. A file whose size or modification time changed within the settle interval is not acquired" do
    test "a file is acquired only once seen unchanged for the interval", %{inbox: inbox} do
      drop!(inbox, "so-what.flac", media!(:flac))

      assert %{files: [{"so-what.flac", :unsettled}]} = pass!(inbox, @t0)
      assert %{files: [{"so-what.flac", :unsettled}]} = pass!(inbox, later(59))
      assert %{files: [{"so-what.flac", {:acquired, _}}]} = pass!(inbox, later(60))
    end

    test "a file that grew between passes waits a further interval", %{inbox: inbox} do
      path = drop!(inbox, "so-what.flac", "the first half")
      pass!(inbox, @t0)

      File.write!(path, "the first half and the second")

      assert %{files: [{_, :unsettled}]} = pass!(inbox, later(60))
      assert %{files: [{_, {:acquired, _}}]} = pass!(inbox, later(120))
    end

    test "a file whose modification time moved at the same size waits too", %{inbox: inbox} do
      path = drop!(inbox, "so-what.flac", "same size")
      pass!(inbox, @t0)

      File.touch!(path, System.os_time(:second) - 3_600)

      assert %{files: [{_, :unsettled}]} = pass!(inbox, later(60))
    end
  end

  describe "3. Metadata, partial downloads and links are held back; hard links are copied" do
    test "operating-system metadata and partial downloads are neither acquired nor removed",
         %{inbox: inbox} do
      held =
        for path <- [
              ".DS_Store",
              "Thumbs.db",
              "Kind of Blue/desktop.ini",
              "Kind of Blue/._01 So What.flac",
              "Kind of Blue/@eaDir/01 So What.flac@SynoEAStream",
              "Bitches Brew.flac.part",
              "In a Silent Way.flac.crdownload"
            ] do
          drop!(inbox, path, "not a holding")
          path
        end

      report = acquire_settled!(inbox, @t0)

      assert acquired(report) == []
      assert Enum.all?(held, &File.exists?(Path.join(inbox, &1)))

      reported = Ingest.held_back(inbox) |> Map.new()
      assert reported["Kind of Blue/@eaDir"] == :ignored
      assert reported["Bitches Brew.flac.part"] == :ignored
      assert reported[".DS_Store"] == :ignored
    end

    test "a symbolic link is held back and neither it nor its target is touched", %{inbox: inbox} do
      target =
        Path.join(inbox |> Path.dirname(), "outside-#{System.unique_integer([:positive])}.flac")

      File.write!(target, "bytes outside the inbox")
      on_exit(fn -> File.rm(target) end)
      File.ln_s!(target, Path.join(inbox, "link.flac"))

      report = acquire_settled!(inbox, @t0)

      assert acquired(report) == []
      assert {"link.flac", :symbolic_link} in Ingest.held_back(inbox)
      assert File.read!(target) == "bytes outside the inbox"
      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(Path.join(inbox, "link.flac"))
    end

    test "a file with a second hard link is copied, and only the inbox's link removed",
         %{inbox: inbox} do
      bytes = media!(:flac)
      in_inbox = drop!(inbox, "so-what.flac", bytes)
      elsewhere = Path.join(Path.dirname(inbox), "linked-#{System.unique_integer([:positive])}")
      File.ln!(in_inbox, elsewhere)
      on_exit(fn -> File.rm(elsewhere) end)

      [id] = inbox |> acquire_settled!(@t0) |> acquired()
      location = Ingest.get_acquisition!(id).location

      refute File.exists?(in_inbox)
      assert File.read!(elsewhere) == bytes
      assert Storage.read(location) == bytes
      assert File.stat!(Storage.path(location)).links == 1
      assert File.stat!(elsewhere).links == 1
    end
  end

  describe "4. An interruption at any step is completed without loss or a second acquisition" do
    test "a record whose file never moved moves it", %{inbox: inbox} do
      bytes = media!(:flac)
      drop!(inbox, "so-what.flac", bytes)
      acquisition = recorded!("so-what.flac")

      pass!(inbox, @t0)

      assert [%Acquisition{state: :identified} = done] = Ingest.acquisitions_from("so-what.flac")
      assert done.id == acquisition.id
      assert Storage.read(acquisition.location) == bytes
      refute File.exists?(Path.join(inbox, "so-what.flac"))
    end

    test "a copy that finished but whose source was not removed continues", %{inbox: inbox} do
      bytes = media!(:flac)
      drop!(inbox, "so-what.flac", bytes)
      acquisition = recorded!("so-what.flac")
      :ok = Storage.put(acquisition.location, bytes)

      pass!(inbox, @t0)

      assert [%Acquisition{state: :identified}] = Ingest.acquisitions_from("so-what.flac")
      refute File.exists?(Path.join(inbox, "so-what.flac"))
      assert Storage.read(acquisition.location) == bytes
    end

    test "a copy cut short is discarded and made again", %{inbox: inbox} do
      bytes = media!(:flac)
      drop!(inbox, "so-what.flac", bytes)
      acquisition = recorded!("so-what.flac")
      :ok = Storage.put(acquisition.location, binary_part(bytes, 0, 100))

      pass!(inbox, @t0)

      assert Storage.read(acquisition.location) == bytes
      assert [%Acquisition{state: :identified}] = Ingest.acquisitions_from("so-what.flac")
    end

    test "bytes moved but not yet identified are identified", %{inbox: inbox} do
      bytes = media!(:flac)
      acquisition = recorded!("so-what.flac")
      :ok = Storage.put(acquisition.location, bytes)

      pass!(inbox, @t0)

      assert %Acquisition{state: :identified, format: "fmt/279"} =
               Ingest.get_acquisition!(acquisition.id)
    end

    test "a record whose file left the inbox before it moved is a finding", %{inbox: inbox} do
      acquisition = recorded!("so-what.flac")

      pass!(inbox, @t0)

      assert %Acquisition{state: :vanished} = Ingest.get_acquisition!(acquisition.id)

      assert [%{stage: :acquire, kind: "inbox_file_left_before_it_moved"}] =
               Ingest.findings_for_acquisition(acquisition.id)
    end

    test "no two acquisitions in progress hold one inbox path" do
      recorded!("so-what.flac")
      id = UUIDv7.generate()

      assert {:error, changeset} =
               %{id: id, inbox_path: "so-what.flac", location: Ingest.location_for(id)}
               |> Acquisition.recorded_changeset()
               |> Repo.insert()

      assert %{inbox_path: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "5. A file dropped again while its holding is live is not acquired again" do
    test "the second drop is removed from the inbox and makes no record", %{inbox: inbox} do
      bytes = media!(:flac)
      drop!(inbox, "so-what.flac", bytes)
      [_first] = inbox |> acquire_settled!(@t0) |> acquired()

      drop!(inbox, "so-what.flac", bytes)
      report = acquire_settled!(inbox, later(3_600))

      assert {"so-what.flac", :already_acquired} in report.files
      assert [_one] = Ingest.acquisitions_from("so-what.flac")
      refute File.exists?(Path.join(inbox, "so-what.flac"))
    end

    test "the same bytes at another path are a new acquisition", %{inbox: inbox} do
      bytes = media!(:flac)
      drop!(inbox, "so-what.flac", bytes)
      acquire_settled!(inbox, @t0)

      drop!(inbox, "again/so-what.flac", bytes)

      assert [_] = inbox |> acquire_settled!(later(3_600)) |> acquired()
    end
  end

  describe "6. A location derives from the identifier and nothing else" do
    test "two files of one name lie at locations naming neither", %{inbox: inbox} do
      drop!(inbox, "a/cover story.flac", media!(:flac, frequency: 300))
      drop!(inbox, "b/cover story.flac", media!(:flac, frequency: 500))

      ids = inbox |> acquire_settled!(@t0) |> acquired()

      for id <- ids do
        location = Ingest.get_acquisition!(id).location
        assert location == Ingest.location_for(id)
        refute location =~ "cover"
        refute location =~ "flac"
      end
    end
  end

  describe "7. A companion is recognized before a category is decided" do
    test "a cover image is a companion, and a photograph of the same bytes is not",
         %{inbox: inbox} do
      bytes = media!(:jpeg)
      drop!(inbox, "Kind of Blue/cover.jpg", bytes)
      drop!(inbox, "holiday/IMG_0001.jpg", bytes)

      acquire_settled!(inbox, @t0)

      assert [%{media_class: :companion, companion_kind: "cover_art"}] =
               Ingest.acquisitions_from("Kind of Blue/cover.jpg")

      assert [%{media_class: :image, companion_kind: nil}] =
               Ingest.acquisitions_from("holiday/IMG_0001.jpg")
    end

    test "lyrics are a companion, not a document or a subtitle", %{inbox: inbox} do
      drop!(inbox, "Kind of Blue/01 So What.lrc", "[00:01.00]So what\n")

      acquire_settled!(inbox, @t0)

      assert [%{media_class: :companion, companion_kind: "lyrics"}] =
               Ingest.acquisitions_from("Kind of Blue/01 So What.lrc")
    end
  end

  describe "20. Essence counts content streams only" do
    test "each kind of file is recorded with the essence its content streams give",
         %{inbox: inbox} do
      files = %{
        "lossless.flac" => {media!(:flac), :lossless},
        "with-cover.flac" => {media!(:flac, art: true), :lossless},
        "lossy.mp3" => {media!(:mp3), :lossy},
        "pcm.wav" => {media!(:wav), :lossless},
        "film.mkv" => {media!(:film), :lossy},
        "master.mkv" => {media!(:ffv1), :lossless},
        "ambiguous.mkv" => {media!(:x264_444), :unknown},
        "still.png" => {media!(:png), :lossless},
        "still.jpg" => {media!(:jpeg), :lossy},
        "letter.pdf" => {pdf(), :not_applicable},
        "notes.txt" => {"a plain note\n", :not_applicable}
      }

      for {path, {bytes, _}} <- files, do: drop!(inbox, path, bytes)

      acquire_settled!(inbox, @t0)

      for {path, {_bytes, essence}} <- files do
        assert [%{essence: ^essence}] = Ingest.acquisitions_from(path), path
      end
    end

    test "embedded cover art is recorded as a stream that carries no content", %{inbox: inbox} do
      drop!(inbox, "with-cover.flac", media!(:flac, art: true))

      acquire_settled!(inbox, @t0)

      [acquisition] = Ingest.acquisitions_from("with-cover.flac")

      assert [
               %{"kind" => "audio", "content" => true, "essence" => "lossless"},
               %{"kind" => "video", "content" => false, "essence" => nil}
             ] = acquisition.streams
    end

    test "a file whose only streams accompany the media is not applicable" do
      cover = %{"kind" => "video", "content" => false, "essence" => nil}
      data = %{"kind" => "data", "content" => false, "essence" => nil}

      assert Identify.essence([cover, data], %{}, "fmt/569") == :not_applicable
    end

    test "a streamless file of a format the registry does not know is unknown" do
      assert Identify.essence([], nil, "fmt/999999") == :unknown
    end

    test "unknown and not applicable are never re-encoded" do
      for essence <- [:unknown, :not_applicable] do
        assert Asset.normalization_plan(%Asset{essence: essence}) ==
                 :adopt
      end
    end
  end

  describe "26. Acquisition and identification failures are recorded against the record" do
    test "bytes nothing can decode are a finding, not a guess", %{inbox: inbox} do
      drop!(inbox, "so-what.mp3", undecodable(600))

      [id] = inbox |> acquire_settled!(@t0) |> acquired()

      assert %Acquisition{state: :stored} = Ingest.get_acquisition!(id)

      assert [%{stage: :identify, kind: "undecodable", permanent: true}] =
               Ingest.findings_for_acquisition(id)
    end

    test "a failed identification is not due again until a person clears it",
         %{inbox: inbox, actor: actor} do
      drop!(inbox, "so-what.mp3", undecodable(600))
      [id] = inbox |> acquire_settled!(@t0) |> acquired()
      [finding] = Ingest.findings_for_acquisition(id)

      refute Enum.any?(Ingest.identify_due(), fn {due, _} -> due == id end)

      {:ok, _} = Ingest.clear_finding(finding.id, actor.id)

      assert {id, :finding} in Ingest.identify_due()
      assert [%{cleared_by: cleared_by}, %{cleared_at: nil}] = Ingest.findings_for_acquisition(id)
      assert cleared_by == actor.id
    end
  end

  defp recorded!(inbox_path) do
    id = UUIDv7.generate()
    cleanup(id)

    %{id: id, inbox_path: inbox_path, location: Ingest.location_for(id)}
    |> Acquisition.recorded_changeset()
    |> Repo.insert!()
  end

  defp later(seconds), do: DateTime.add(@t0, seconds, :second)

  defp index_definition(name) do
    %{rows: [[definition]]} =
      Repo.query!("SELECT pg_get_indexdef(oid) FROM pg_class WHERE relname = $1", [name])

    definition
  end
end
