defmodule Pluteus.Presentation.GenerateTest do
  @moduledoc """
  Making a derivative ([spec-10] §11), and criterion 29: every derivative has its
  orientation applied and its orientation metadata removed.
  """

  use Pluteus.DataCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Place
  alias Pluteus.Ingest.Probe
  alias Pluteus.Ingest.Streams
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Generate
  alias Pluteus.Presentation.Orientation
  alias Pluteus.Presentation.Registry
  alias Pluteus.Principals
  alias Pluteus.Storage

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup do
    _system = Principals.system!()
    %{inbox: inbox!()}
  end

  # Under a prefix of its own, because two async tests dropping one relative path
  # contend on the sighting and acquisition rows for as long as the slower one runs.
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

  defp generated!(inbox, bytes, profile, name \\ "photos/holiday/IMG_0001.jpg") do
    [photo] = ingest!(inbox, %{name => bytes})
    subject = manifestation_of(photo)

    {:ok, made} = Generate.run(subject, profile)
    on_exit(fn -> Storage.delete(made.location) end)

    {subject, made}
  end

  describe "an image derivative is made from the master" do
    test "it is scaled to the profile's width and recorded", %{inbox: inbox} do
      {subject, made} = generated!(inbox, media!(:jpeg), "image-160")

      assert made.subject_id == subject
      assert made.profile == "image-160"
      assert made.media_type == "image/jpeg"
      assert made.size > 0
      assert made.width == 64
      assert made.height == 48
      assert Storage.exists?(made.location)
      assert Presentation.get(subject, "image-160").digest == made.digest
    end

    test "a profile is a ceiling, so a small original is not enlarged", %{inbox: inbox} do
      {_subject, made} = generated!(inbox, media!(:jpeg), "image-2048")

      # The source is 64 wide. Asking for 2048 gives 64, not a stretched 2048 with
      # no more detail in it than the original had.
      assert made.width == 64
      assert made.height == 48
    end

    test "it names the master it came from, and that master's digest", %{inbox: inbox} do
      [photo] = ingest!(inbox, %{"photos/holiday/IMG_0001.jpg" => media!(:jpeg)})
      subject = manifestation_of(photo)
      master = Normalize.master_of(photo.digital_item_id)

      {:ok, made} = Generate.run(subject, "image-160")
      on_exit(fn -> Storage.delete(made.location) end)

      assert made.source_asset_id == master.id
      assert made.source_digest == master.digest
      assert Presentation.current?(made, master.digest)
    end

    test "regenerating writes over the same location", %{inbox: inbox} do
      {subject, first} = generated!(inbox, media!(:jpeg), "image-160")

      {:ok, second} = Generate.run(subject, "image-160")

      assert second.location == first.location
      assert [_] = Presentation.for_subject(subject)
    end
  end

  describe "§12.1. A container of pages yields one image per page" do
    test "the page asked for is the page made", %{inbox: inbox} do
      [comic] =
        ingest!(inbox, %{
          "comics/Excitebike 001.cbz" =>
            cbz([
              {"001.png", comic_page(1)},
              {"002.png", comic_page(2)},
              {"003.png", comic_page(3)}
            ])
        })

      subject = manifestation_of(comic)

      {:ok, second} = Generate.run(subject, "image-640", 1)
      on_exit(fn -> Storage.delete(second.location) end)

      assert second.ordinal == 1
      assert second.width > 0

      # The key is the subject, the profile and the page, so one archive yields an
      # artefact per page rather than one that is whichever page was asked for first.
      {:ok, third} = Generate.run(subject, "image-640", 2)
      on_exit(fn -> Storage.delete(third.location) end)

      assert third.location != second.location
      assert Presentation.get(subject, "image-640", 2).location == third.location
      assert Presentation.get(subject, "image-640", 1).location == second.location
    end

    test "a page the archive does not hold is not made", %{inbox: inbox} do
      [comic] =
        ingest!(inbox, %{"comics/Excitebike 002.cbz" => cbz([{"001.png", comic_page(1)}])})

      assert {:error, "page_not_held", detail} =
               Generate.run(manifestation_of(comic), "image-640", 7)

      assert detail.page == 7
      assert detail.pages == 1
    end

    # A holding carried by one file is that file, whole. Asking for its fourth page is
    # asking for something it does not have rather than for the file again.
    test "a holding that is not a container has no second page", %{inbox: inbox} do
      [photo] = ingest!(inbox, %{"photos/holiday/IMG_0001.jpg" => media!(:jpeg)})

      assert {:error, "holding_has_no_pages", %{page: 3}} =
               Generate.run(manifestation_of(photo), "image-640", 3)
    end

    # The entry is extracted to make the derivative and is not an artefact of its own:
    # what stays is the image profile, and the page it was taken from goes.
    test "the page it was taken from does not stay", %{inbox: inbox} do
      [comic] =
        ingest!(inbox, %{"comics/Excitebike 003.cbz" => cbz([{"001.png", comic_page(1)}])})

      subject = manifestation_of(comic)

      {:ok, made} = Generate.run(subject, "image-640", 0)
      on_exit(fn -> Storage.delete(made.location) end)

      refute Storage.exists?(Presentation.location_for(subject, "page", 0, "png"))
    end
  end

  describe "29. Every derivative has its orientation applied" do
    test "an image stating a quarter turn comes out turned", %{inbox: inbox} do
      # Orientation 6 is a 90 degree clockwise rotation, so a 64x48 source becomes
      # 48x64. Without the filter it would stay 64x48 and be drawn on its side.
      {_subject, made} = generated!(inbox, oriented_jpeg(6), "image-160")

      assert made.width == 48
      assert made.height == 64
    end

    test "every turning value exchanges the dimensions", %{inbox: inbox} do
      for orientation <- [5, 6, 7, 8] do
        {_subject, made} =
          generated!(
            inbox,
            oriented_jpeg(orientation),
            "image-160",
            "photos/t#{orientation}/img.jpg"
          )

        assert {made.width, made.height} == {48, 64},
               "orientation #{orientation} was not applied"
      end
    end

    test "a mirror leaves the dimensions and still applies", %{inbox: inbox} do
      for orientation <- [1, 2, 3, 4] do
        {_subject, made} =
          generated!(
            inbox,
            oriented_jpeg(orientation),
            "image-160",
            "photos/m#{orientation}/img.jpg"
          )

        assert {made.width, made.height} == {64, 48},
               "orientation #{orientation} changed the shape"
      end
    end

    test "the derivative states which orientation it applied", %{inbox: inbox} do
      {_subject, made} = generated!(inbox, oriented_jpeg(6), "image-160")

      assert made.descriptor["orientation_applied"] == 6
    end
  end

  describe "29. …and its orientation metadata removed" do
    test "the derivative states no orientation of its own", %{inbox: inbox} do
      {_subject, made} = generated!(inbox, oriented_jpeg(6), "image-160")

      # A derivative carrying the orientation it has already been turned by would be
      # turned twice by anything that honours EXIF.
      assert made.location
             |> Storage.leading(Orientation.head_bytes())
             |> Orientation.of() == nil
    end

    test "the probe of the derivative agrees with the recorded geometry",
         %{inbox: inbox} do
      {_subject, made} = generated!(inbox, oriented_jpeg(6), "image-160")

      {:ok, probe} = Probe.probe(made.location)

      assert Streams.dimensions(probe) == {made.width, made.height}
    end
  end

  describe "nothing is made where nothing was asked for" do
    test "a profile outside the registry is refused", %{inbox: inbox} do
      [photo] = ingest!(inbox, %{"photos/holiday/IMG_0001.jpg" => media!(:jpeg)})

      assert Generate.run(manifestation_of(photo), "image-999") ==
               {:refused, :unknown_profile}
    end

    test "a profile that does not apply to the subject is refused", %{inbox: inbox} do
      [photo] = ingest!(inbox, %{"photos/holiday/IMG_0001.jpg" => media!(:jpeg)})

      assert Generate.run(manifestation_of(photo), "waveform-overview-1000") ==
               {:refused, :profile_does_not_apply}
    end

    test "a subject with no master is refused" do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("A Described Photograph")

      assert Generate.run(manifestation.id, "image-160") in [
               {:refused, :no_master},
               {:refused, :profile_does_not_apply}
             ]
    end

    test "every profile the registry names has a generator", %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "photos/holiday/IMG_0001.png" => media!(:png),
          "KoB/01.flac" => media!(:flac, duration: 2),
          "home video/party.mkv" => media!(:ffv1, duration: 45),
          "scans/letters/note.txt" => "a note\n"
        })

      subjects = Map.new(placed, &{&1.media_class, manifestation_of(&1)})

      # A registry entry nothing can make is a name a surface may ask for and never be
      # answered, so a profile added to §20 with no generator fails here rather than
      # answering 202 for ever. One applicable subject each is enough to prove the
      # dispatch reaches a generator, and a refusal for any other reason proves it too:
      # the tiling profile refuses a small image for being under the threshold, which
      # only a generator can decide.
      for profile <- Registry.profiles() do
        name = Map.fetch!(profile, "name")
        classes = Enum.map(Map.fetch!(profile, "classes"), &String.to_existing_atom/1)

        case Enum.find_value(classes, &subjects[&1]) do
          nil ->
            :no_subject_of_that_class

          subject ->
            result = Generate.run(subject, name)

            refute result == {:refused, :no_generator}, "#{name} reaches no generator"

            with {:ok, made} <- result, do: on_exit(fn -> Storage.delete(made.location) end)
        end
      end
    end
  end

  describe "the orientation reader" do
    test "an image with no EXIF states nothing" do
      assert Orientation.of(media!(:jpeg)) == nil
      assert Orientation.of(media!(:png)) == nil
    end

    test "each of the eight values is read back" do
      for orientation <- 1..8 do
        assert Orientation.of(oriented_jpeg(orientation)) == orientation
      end
    end

    test "bytes that are not an image state nothing" do
      assert Orientation.of("not an image at all") == nil
      assert Orientation.of(<<0xFF, 0xD8>>) == nil
      assert Orientation.of("") == nil
    end

    test "a truncated APP1 is treated as upright rather than raising" do
      assert Orientation.of(<<0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x40, "Exif", 0, 0>>) == nil
    end

    test "only a turn exchanges the dimensions" do
      for turning <- [5, 6, 7, 8], do: assert(Orientation.turns?(turning))
      for upright <- [1, 2, 3, 4], do: refute(Orientation.turns?(upright))
      refute Orientation.turns?(nil)
    end
  end

  describe "the encoder is the one applying the turn" do
    test "ffmpeg decodes a tagged image already turned", %{inbox: inbox} do
      # This is the fact the generator rests on, asserted directly so that an encoder
      # which stopped autorotating fails here and names why, rather than filling a
      # library with sideways thumbnails.
      [photo] = ingest!(inbox, %{"photos/holiday/turned.jpg" => oriented_jpeg(6)})
      master = Normalize.master_of(photo.digital_item_id)

      {:ok, probe} = Probe.probe(master.location)

      # The probe reports what is stored, which is the untuned shape.
      assert Streams.dimensions(probe) == {64, 48}

      # The derivative is the turned one, and nothing in the filter chain turns it.
      {:ok, made} = Generate.run(manifestation_of(photo), "image-160")
      on_exit(fn -> Storage.delete(made.location) end)

      assert {made.width, made.height} == {48, 64}
    end
  end
end
