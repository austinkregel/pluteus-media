defmodule Pluteus.Ingest.RegistryTest do
  @moduledoc """
  The media type a format is served as (spec-07 §4.4). The formats here are
  those a real library was found to hold: PRONOM distinguishes versions of a
  format and codecs within a container, and each identifier it reports must be
  mapped or the bytes are served as an unknown stream.
  """

  use ExUnit.Case, async: true

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
end
