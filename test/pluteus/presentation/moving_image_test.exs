defmodule Pluteus.Presentation.MovingImageTest do
  @moduledoc """
  [spec-10] §11.3's required moving-image artefacts: a key frame for the poster
  position, and a trickplay sheet with the index from a time to a tile.

  Also criterion 9: no image is generated to stand for a holding that has none.
  """

  use Pluteus.DataCase, async: true
  use Oban.Testing, repo: Pluteus.Repo

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Place
  alias Pluteus.Ingest.Streams
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Generate
  alias Pluteus.Presentation.Registry
  alias Pluteus.Principals
  alias Pluteus.Storage
  alias Pluteus.Workers.GeneratePresentationAsset
  alias Pluteus.Workers.NormalizeHoldings

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup do
    _system = Principals.system!()
    %{inbox: inbox!()}
  end

  # Under a prefix of its own, because two async tests dropping one relative path
  # contend on the sighting and acquisition rows for as long as the slower one runs, and
  # encoding three quarters of a minute of video is slow.
  defp ingest!(inbox, files) do
    prefix = unique_prefix()
    for {path, bytes} <- files, do: drop!(inbox, Path.join(prefix, path), bytes)
    ids = inbox |> acquire_settled!(@t0) |> acquired()
    Place.place_due(inbox)
    Normalize.normalize_due()
    ids |> Enum.map(&Ingest.get_acquisition!/1) |> Enum.sort_by(& &1.inbox_path)
  end

  defp manifestation_of(acquisition),
    do: Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id

  defp a_film(inbox, opts \\ []) do
    name = Keyword.get(opts, :name, "home video/birthday.mkv")
    duration = Keyword.get(opts, :duration, 1)

    [film] = ingest!(inbox, %{name => media!(:ffv1, duration: duration)})
    manifestation_of(film)
  end

  defp made!(subject, profile) do
    {:ok, made} = Generate.run(subject, profile)
    on_exit(fn -> Storage.delete(made.location) end)
    made
  end

  describe "a key frame is the poster position" do
    test "one still is made, and it states where it was taken", %{inbox: inbox} do
      made = made!(a_film(inbox), "keyframe")

      assert made.media_type == "image/jpeg"
      assert made.width > 0
      assert made.height > 0
      assert is_integer(made.descriptor["taken_at_ms"])
      assert Storage.exists?(made.location)
    end

    test "it is bounded at both ends, so a short clip does not take frame zero",
         %{inbox: inbox} do
      # `moving/0` is a one-second clip. A tenth of a second is inside the minimum, so
      # the position is clamped rather than being a tenth of nothing.
      made = made!(a_film(inbox), "keyframe")
      declared = Registry.key_frame()

      assert made.descriptor["taken_at_ms"] <= declared["maximum_ms"]
      assert made.descriptor["taken_at_ms"] >= 0
    end

    test "a still image has no key frame, because it is not moving", %{inbox: inbox} do
      [photo] = ingest!(inbox, %{"photos/holiday/IMG_0001.png" => media!(:png)})

      assert Generate.run(manifestation_of(photo), "keyframe") ==
               {:refused, :profile_does_not_apply}
    end
  end

  describe "a trickplay sheet is frames at a fixed interval, tiled" do
    test "the sheet is one image and states its tiling", %{inbox: inbox} do
      made = made!(a_film(inbox, duration: 45, name: "home video/party.mkv"), "trickplay-320")

      declared = Registry.trickplay()

      assert made.descriptor["tile_columns"] == declared["tile_columns"]
      assert made.descriptor["tile_rows"] == declared["tile_rows"]
      assert made.descriptor["frame_interval_ms"] == declared["frame_interval_ms"]
      assert made.descriptor["frame_width"] == declared["frame_width"]
      assert made.width > 0 and made.height > 0
    end

    test "the index says how many frames the sheet actually holds", %{inbox: inbox} do
      made = made!(a_film(inbox, duration: 45, name: "home video/party.mkv"), "trickplay-320")

      # A client goes from a time to a tile with the interval and the frame count; a
      # count it had to infer from the image's size would be a guess. Forty-five
      # seconds at ten-second intervals is four.
      assert made.descriptor["frames"] == 4

      assert made.descriptor["frames"] <=
               made.descriptor["tile_columns"] * made.descriptor["tile_rows"]
    end

    test "a clip shorter than one interval has no sheet, and says so", %{inbox: inbox} do
      # A one-second clip has no frames ten seconds apart. A sheet of none is not a
      # narrower sheet, and writing one at another interval would make the index lie.
      assert Generate.run(a_film(inbox), "trickplay-320") ==
               {:refused, :shorter_than_one_interval}
    end

    test "a recording has no trickplay sheet", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"KoB/01.flac" => media!(:flac)})

      assert Generate.run(manifestation_of(track), "trickplay-320") ==
               {:refused, :profile_does_not_apply}
    end
  end

  describe "a chapter list is the container's own, and needs no artefact" do
    test "the chapters a container declares are read from the probe", %{inbox: inbox} do
      [film] =
        ingest!(inbox, %{
          "home video/holiday.mkv" =>
            media!(:ffv1,
              duration: 12,
              chapters: [{"Arrival", {0, 4_000}}, {"The Beach", {4_000, 12_000}}]
            )
        })

      # §20 names no chapter profile, and this is why: the list is the container's own
      # metadata, which the probe already reads.
      assert [first, second] = Streams.chapters(film.probe)

      assert first["title"] == "Arrival"
      assert first["start_ms"] == 0
      assert_in_delta first["end_ms"], 4_000, 50

      assert second["title"] == "The Beach"
      assert_in_delta second["start_ms"], 4_000, 50
    end

    test "a container declaring none has none", %{inbox: inbox} do
      [film] = ingest!(inbox, %{"home video/birthday.mkv" => media!(:ffv1)})

      assert Streams.chapters(film.probe) == []
    end

    test "a probe that never ran has none" do
      assert Streams.chapters(nil) == []
    end
  end

  describe "9. No image is generated to stand for a holding that has none" do
    test "a manifestation with no file gets no artefact of any kind" do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("A Described Photograph")

      for profile <- Registry.profile_names() do
        assert {:refused, _reason} = Generate.run(manifestation.id, profile),
               "#{profile} was generated for a holding with no bytes"
      end

      assert Presentation.for_subject(manifestation.id) == []
    end

    test "nothing stands in for it at ingest either" do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("A Described Photograph")

      GeneratePresentationAsset.queue_at_ingest(manifestation.id)

      # The jobs are queued and each cancels itself, because what applies is decided in
      # one place rather than two that could disagree. Nothing is written.
      Oban.drain_queue(queue: :presentation)

      assert Presentation.for_subject(manifestation.id) == []
    end
  end

  describe "§11.6's at-ingest set is generated once a holding has a master" do
    test "normalizing a photograph queues the registry's profiles", %{inbox: inbox} do
      drop!(inbox, Path.join(unique_prefix(), "photos/holiday/IMG_0001.png"), media!(:png))
      inbox |> acquire_settled!(@t0) |> acquired()
      Place.place_due(inbox)

      assert all_enqueued(worker: GeneratePresentationAsset) == []

      NormalizeHoldings.perform(%Oban.Job{})

      queued = Enum.map(all_enqueued(worker: GeneratePresentationAsset), & &1.args["profile"])

      assert Enum.sort(queued) == Enum.sort(Registry.generated_at_ingest())
    end

    test "the ones that do not apply cancel themselves, and the rest are made",
         %{inbox: inbox} do
      path = Path.join(unique_prefix(), "photos/holiday/IMG_0001.png")

      drop!(inbox, path, media!(:png))
      inbox |> acquire_settled!(@t0) |> acquired()
      Place.place_due(inbox)
      NormalizeHoldings.perform(%Oban.Job{})

      %{success: made, cancelled: refused} = Oban.drain_queue(queue: :presentation)

      # A photograph takes the image profiles; the waveform and the key frame do not
      # apply to it.
      assert made == 2
      assert refused == 2

      [photo] = Ingest.acquisitions_from(path)
      artefacts = Presentation.for_subject(manifestation_of(photo))
      locations = Enum.map(artefacts, & &1.location)
      on_exit(fn -> for location <- locations, do: Storage.delete(location) end)

      assert Enum.sort(Enum.map(artefacts, & &1.profile)) == ["image-160", "image-320"]
    end
  end
end
