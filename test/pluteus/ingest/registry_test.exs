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

  test "a format the registry does not name is served as an unknown stream" do
    assert Registry.media_type("fmt/0") == "application/octet-stream"
  end
end
