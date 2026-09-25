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
  alias Pluteus.Principals
  alias Pluteus.Storage

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup do
    _system = Principals.system!()
    %{inbox: inbox!()}
  end

  defp ingest!(inbox, files) do
    for {path, bytes} <- files, do: drop!(inbox, path, bytes)
    ids = inbox |> acquire_settled!(@t0) |> acquired()
    Place.place_due(inbox)
    Normalize.normalize_due()
    ids |> Enum.map(&Ingest.get_acquisition!/1) |> Enum.sort_by(& &1.inbox_path)
  end

  defp manifestation_of(acquisition),
    do: Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id

  defp generated!(inbox, bytes, profile, name \\ "holiday/IMG_0001.jpg") do
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
      [photo] = ingest!(inbox, %{"holiday/IMG_0001.jpg" => media!(:jpeg)})
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
          generated!(inbox, oriented_jpeg(orientation), "image-160", "t#{orientation}/img.jpg")

        assert {made.width, made.height} == {48, 64},
               "orientation #{orientation} was not applied"
      end
    end

    test "a mirror leaves the dimensions and still applies", %{inbox: inbox} do
      for orientation <- [1, 2, 3, 4] do
        {_subject, made} =
          generated!(inbox, oriented_jpeg(orientation), "image-160", "m#{orientation}/img.jpg")

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
      [photo] = ingest!(inbox, %{"holiday/IMG_0001.jpg" => media!(:jpeg)})

      assert Generate.run(manifestation_of(photo), "image-999") ==
               {:refused, :unknown_profile}
    end

    test "a profile that does not apply to the subject is refused", %{inbox: inbox} do
      [photo] = ingest!(inbox, %{"holiday/IMG_0001.jpg" => media!(:jpeg)})

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

    test "a family with no generator says so rather than writing something else",
         %{inbox: inbox} do
      [document] = ingest!(inbox, %{"letters/note.txt" => "a note\n"})

      # Extracting text needs an extractor this deployment does not carry. Asking for
      # one is answered plainly rather than by writing an image under its name.
      assert Generate.run(manifestation_of(document), "text-extracted") ==
               {:refused, :no_generator}
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
      [photo] = ingest!(inbox, %{"holiday/turned.jpg" => oriented_jpeg(6)})
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
