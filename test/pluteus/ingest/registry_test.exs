defmodule Pluteus.Ingest.RegistryTest do
  @moduledoc """
  The media type a format is served as (spec-07 §4.4). The formats here are
  those a real library was found to hold: PRONOM distinguishes versions of a
  format and codecs within a container, and each identifier it reports must be
  mapped or the bytes are served as an unknown stream.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Registry

  test "each audio format a library holds is served as its own type" do
    assert Registry.media_type("fmt/279") == "audio/flac"
    assert Registry.media_type("fmt/134") == "audio/mpeg"
    assert Registry.media_type("fmt/141") == "audio/wav"
    assert Registry.media_type("fmt/2094") == "audio/mp4"
    assert Registry.media_type("fmt/203") == "audio/ogg"
    assert Registry.media_type("fmt/946") == "audio/ogg"
  end

  test "each image format cover art arrives as is served as its own type" do
    for format <- ~w(fmt/11 fmt/12) do
      assert Registry.media_type(format) == "image/png"
    end

    for format <- ~w(fmt/41 fmt/43 fmt/44 fmt/645 x-fmt/391) do
      assert Registry.media_type(format) == "image/jpeg"
    end
  end

  test "each subtitle format a media manager writes is served as its own type" do
    assert Registry.media_type("fmt/1218") == "application/x-subrip"
    assert Registry.media_type("fmt/1454") == "text/vtt"
  end

  describe "the registry's vocabularies are the schema's" do
    test "every essence and class the registry admits is one a holding can be recorded as" do
      # The registry maps its strings to atoms written out as literals rather than converted,
      # so the atoms exist whenever this module does. Written out they could drift from the
      # column's own vocabulary, which is what this refuses.
      %{essences: essences, classes: classes} = Registry.vocabularies()

      assert Enum.sort(essences) == Enum.sort(Acquisition.essences())
      assert Enum.sort(classes) == Enum.sort(Acquisition.media_classes())
    end

    test "a format the registry carries no entry for is nil, not a guess" do
      refute Registry.streamless_format("fmt/to-be-invented")
    end
  end

  test "a format the registry does not name is served as an unknown stream" do
    assert Registry.media_type("fmt/0") == "application/octet-stream"
  end

  describe "a companion is recognized by name, and by its first bytes where a name cannot say" do
    test "an .nfo holding markup is metadata; one holding a release's notes is a description" do
      assert Registry.companion_kind("album.nfo", fn ->
               "<album>\n  <title>The Color Before the Sun</title>\n</album>\n"
             end) == "metadata"

      assert Registry.companion_kind("release.nfo", fn ->
               " :::::  Some.Movie.2021.1080p.BluRay.x264-GROUP  :::::\n"
             end) == "description"
    end

    test "an XML file whose root the registry does not name is no companion" do
      assert Registry.companion_kind("film.xml", fn ->
               ~s(<?xml version="1.0" encoding="UTF-8"?>\n<details><id>90</id></details>\n)
             end) == "metadata"

      assert Registry.companion_kind("invoice.xml", fn ->
               ~s(<?xml version="1.0" encoding="UTF-8"?>\n<invoice><total>3</total></invoice>\n)
             end) == nil
    end

    test "a declaration, a doctype and a comment are not the root element" do
      declared = fn ->
        ~s(<?xml version="1.0"?>\n<!DOCTYPE movie>\n<movie><title>Aladdin</title></movie>)
      end

      assert Registry.companion_kind("Aladdin.nfo", declared) == "metadata"

      commented = fn -> ~s(<!-- <album> -->\n<invoice><total>3</total></invoice>) end

      assert Registry.companion_kind("March.xml", commented) == nil
    end

    test "a root element is read without its namespace prefix, whatever its case" do
      assert Registry.companion_kind("show.nfo", fn -> "<kodi:TVShow></kodi:TVShow>" end) ==
               "metadata"
    end

    test "bytes that are not text have no root element, whatever they spell" do
      thumbnail = fn -> <<0xFF, 0xD8, 0xFF, 0xE0>> <> "<album><title>x</title></album>" end

      assert Registry.companion_kind("art.nfo", thumbnail) == "description"
    end

    test "34. a photographic edit sidecar is a companion, never a document" do
      # Each names an edit made to the photograph beside it and holds none of the
      # image itself, so placing one as a document of its own would catalogue a
      # description as a holding.
      assert Registry.companion_kind("IMG_0001.pp3") == "metadata"
      assert Registry.companion_kind("IMG_0001.dop") == "metadata"
      assert Registry.companion_kind("IMG_0001.aae") == "metadata"
    end

    test "34. a .info.json is a companion, which no extension alone can express" do
      # `Path.extname/1` answers `.json` and the rootname is `video.info`, so
      # neither the extension form nor the whole-name form reaches it.
      assert Registry.companion_kind("video.info.json") == "metadata"
      assert Registry.companion_kind("Some Film (2019).info.json") == "metadata"

      # A plain .json is not a companion: the second extension is what says so.
      assert Registry.companion_kind("notes.json") == nil
    end

    test "34. a gamelist.xml is a companion, recognized by its root element" do
      gamelist = fn -> ~s(<?xml version="1.0"?>\n<gameList>\n  <game />\n</gameList>\n) end

      assert Registry.companion_kind("gamelist.xml", gamelist) == "metadata"

      # Matching the root rather than the name catches one a person renamed.
      assert Registry.companion_kind("snes.xml", gamelist) == "metadata"
    end

    test "35. a comic's metadata document is named by its root element" do
      comic_info = fn -> ~s(<ComicInfo>\n  <Series>Saga</Series>\n</ComicInfo>) end
      metron_info = fn -> ~s(<MetronInfo>\n  <Series>Saga</Series>\n</MetronInfo>) end

      assert Registry.companion_kind("ComicInfo.xml", comic_info) == "metadata"
      assert Registry.companion_kind("MetronInfo.xml", metron_info) == "metadata"
    end

    test "an XML file whose root none of those names is still no companion" do
      invoice = fn -> ~s(<?xml version="1.0"?>\n<invoice><total>3</total></invoice>) end

      assert Registry.companion_kind("gamelist.xml", invoice) == nil
      assert Registry.companion_kind("ComicInfo.xml", invoice) == nil
    end

    test "artwork, lyrics, subtitles and sidecars are recognized by name alone" do
      assert Registry.companion_kind("poster.jpg") == "cover_art"
      assert Registry.companion_kind("Overlord - S04E01.metathumb") == "cover_art"
      assert Registry.companion_kind("So What.elrc") == "lyrics"
      assert Registry.companion_kind("Stalker.en.forced.srt") == "subtitles"
      assert Registry.companion_kind("Stalker.vtt") == "subtitles"
      assert Registry.companion_kind("IMG_0001.xmp") == "metadata"
      assert Registry.companion_kind("metadata.opf") == "metadata"
      assert Registry.companion_kind(".plexmatch") == "metadata"
      assert Registry.companion_kind("IMG_0001.jpg") == nil
    end
  end

  describe "a deployment signature names a format PRONOM holds no byte signature for" do
    test "a cartridge dump is named by the magic bytes its container opens with" do
      assert Registry.byte_signature("NES\x1a" <> <<16, 0, 1, 0>>) == "ines"
      assert Registry.byte_signature(<<0x80, 0x37, 0x12, 0x40, 0, 0, 0, 0>>) == "n64"
    end

    test "a signature at an offset is read there, not anywhere it happens to appear" do
      at_0x100 = :binary.copy(<<0>>, 256) <> "SEGA MEGA DRIVE "

      assert Registry.byte_signature(at_0x100) == "megadrive"
      refute Registry.byte_signature("SEGA " <> :binary.copy(<<0>>, 512)) == "megadrive"
    end

    test "a disc image is named by its primary volume descriptor at 0x8001" do
      iso = :binary.copy(<<0>>, 32_769) <> "CD001"

      assert Registry.byte_signature(iso) == "iso9660"
    end

    test "bytes matching nothing are named by nothing" do
      assert Registry.byte_signature(:binary.copy(<<0>>, 40_000)) == nil
      assert Registry.byte_signature("") == nil
    end

    test "a head shorter than a signature's offset is not a match" do
      assert Registry.byte_signature("CD001") == nil
    end

    test "one read of the span answers every signature" do
      span = Registry.signature_span()

      # The furthest signature is ISO 9660's, at 0x8001 for five bytes.
      assert span == 32_774

      assert Registry.byte_signature(:binary.copy(<<0>>, span - 5) <> "CD001") == "iso9660"
    end

    test "37. a software holding takes its essence from its format" do
      for format <- ~w(ines megadrive n64 iso9660) do
        assert Registry.streamless_format(format) == %{
                 class: :software,
                 essence: :not_applicable
               }
      end
    end

    test "37. no standard format is named for software, so nothing re-encodes it" do
      assert Registry.standard_format(:software) == nil
      assert Registry.standard_format(:package) == nil
    end

    test "a package and a software holding each have a category without evidence" do
      assert Registry.default_category(:package, nil) == "comic_issue"
      assert Registry.default_category(:software, nil) == "video_game"
    end
  end
end
