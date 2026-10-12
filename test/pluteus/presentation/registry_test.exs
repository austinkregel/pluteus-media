defmodule Pluteus.Presentation.RegistryTest do
  @moduledoc """
  The presentation profiles spec-10 §20 holds, and the closed set spec-10 §11.1
  requires a surface to ask within.

  Criterion 46 asks that every registry §20 names be populated and that no code
  path supply a value a registry omits. This file asserts the profile half of it
  and names what is still unseeded.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Ingest.Registry, as: Ingest
  alias Pluteus.Presentation.Registry
  alias Pluteus.Surfaces.Registry, as: Surfaces

  test "a profile name identifies one profile across every family" do
    names = Registry.profile_names()

    assert names == Enum.uniq(names)
    assert Enum.all?(names, &is_binary/1)
  end

  test "every image profile carries a width, a format and what it is for" do
    for profile <- Registry.image_profiles() do
      assert is_integer(profile["width"]) and profile["width"] > 0
      assert is_binary(profile["format"])
      assert is_binary(profile["for"])
    end
  end

  test "the image widths are graded widely enough that no intermediate is wanted" do
    widths = Enum.map(Registry.image_profiles(), & &1["width"])

    assert widths == Enum.sort(widths)
    assert widths == Enum.uniq(widths)

    # A surface picks a profile from CSS pixels times its device pixel ratio. A
    # step below 1.5x leaves two profiles a surface cannot choose between; a step
    # above 2x makes it over-fetch badly at the bottom of the band.
    for [narrower, wider] <- Enum.chunk_every(widths, 2, 1, :discard) do
      ratio = wider / narrower

      assert ratio >= 1.5, "#{narrower} to #{wider} is too small a step to be worth a profile"
      assert ratio <= 2.0, "#{narrower} to #{wider} makes a surface over-fetch"
    end
  end

  describe "an OpenSubsonic size maps to the smallest profile at or above it" do
    test "a size lands on the first profile wide enough to serve it" do
      assert Registry.image_profile_for_size(32)["name"] == "image-160"
      assert Registry.image_profile_for_size(100)["name"] == "image-160"
      assert Registry.image_profile_for_size(160)["name"] == "image-160"
      assert Registry.image_profile_for_size(161)["name"] == "image-320"
      assert Registry.image_profile_for_size(300)["name"] == "image-320"
      assert Registry.image_profile_for_size(600)["name"] == "image-640"
      assert Registry.image_profile_for_size(640)["name"] == "image-640"
      assert Registry.image_profile_for_size(1200)["name"] == "image-1280"
      assert Registry.image_profile_for_size(2048)["name"] == "image-2048"
    end

    test "a request naming no size takes the default" do
      assert Registry.image_profile_for_size(nil) == Registry.default_image_profile()
      assert Registry.default_image_profile()["name"] == "image-640"
    end

    test "a size above the widest profile is served the widest, not refused" do
      widest = List.last(Registry.image_profiles())

      assert Registry.image_profile_for_size(4000) == widest
      assert Registry.image_profile_for_size(100_000) == widest
    end

    test "no size resolves to a name outside the closed set" do
      for size <- [1, 159, 161, 639, 641, 2047, 2049, 9999] do
        assert Registry.image_profile_for_size(size)["name"] in Registry.profile_names()
      end
    end
  end

  describe "the set of profile names is closed" do
    test "a name in the set resolves to its profile" do
      assert {:ok, %{"width" => 320}} = Registry.profile("image-320")
      assert {:ok, %{"points" => 1000}} = Registry.profile("waveform-overview-1000")
      assert {:ok, %{"frame_interval_ms" => 10_000}} = Registry.profile("trickplay-320")
    end

    test "a name outside the set resolves to nothing, rather than to something near it" do
      assert Registry.profile("image-700") == :error
      assert Registry.profile("700x400") == :error
      assert Registry.profile("") == :error
    end
  end

  describe "a surface reserves a box before it fetches an image" do
    test "every category placement can write has an assumed aspect ratio" do
      # Every category, not every class: a class decides a category only where it means
      # one kind of thing, and a surface reserves a box for whatever placement recorded.
      for category <- Ingest.recordable_categories(), Surfaces.surface_of(category) != nil do
        assert is_float(Registry.assumed_aspect_ratio(category)),
               "#{category} is presented somewhere and has no assumed aspect ratio"
      end
    end

    test "every category the series names has one" do
      for category <- ~w(album music_recording audiobook podcast_episode film
                         television_episode home_video photograph scan document
                         ebook comic_issue video_game) do
        assert is_float(Registry.assumed_aspect_ratio(category)),
               "#{category} has no assumed aspect ratio"
      end
    end

    test "a companion kind that is never presented has none, and says so" do
      assert Registry.assumed_aspect_ratio("lyrics") == nil
      assert Registry.assumed_aspect_ratio("subtitles") == nil
      assert Registry.assumed_aspect_ratio("cue_sheet") == nil

      assert Registry.assumed_aspect_ratio("cover_art") == 1.0
    end

    test "a category the registry does not name raises rather than guessing a shape" do
      assert_raise KeyError, fn -> Registry.assumed_aspect_ratio("hologram") end
    end
  end

  test "a waveform declares its own resolution, so a zoom finer than it is refusable" do
    assert Registry.waveform_overview()["points"] == 1000

    for detail <- Registry.waveform_detail() do
      assert is_integer(detail["points_per_second"])
    end

    finest = Registry.waveform_detail() |> Enum.map(& &1["points_per_second"]) |> Enum.max()
    assert finest == 100
  end

  test "the poster frame is a proportion of the duration, bounded at both ends" do
    key_frame = Registry.key_frame()

    assert key_frame["regime"] == "proportional"
    assert key_frame["proportion"] > 0 and key_frame["proportion"] < 1
    assert key_frame["minimum_ms"] < key_frame["maximum_ms"]
  end

  test "the tiling threshold sits above a scan a graded profile still serves" do
    widest = List.last(Registry.image_profiles())["width"]

    # An A4 page at 300 dpi is 2480 x 3508, which image-2048 serves; at 600 dpi it
    # is 4960 x 7016, which it does not. The threshold separates the two.
    assert 2480 * 3508 < Registry.tiling()["threshold_pixels"]
    assert 4960 * 7016 > Registry.tiling()["threshold_pixels"]
    assert widest >= 2048
  end

  test "every profile generated at ingest is a profile" do
    for name <- Registry.generated_at_ingest() do
      assert {:ok, _profile} = Registry.profile(name)
    end
  end
end
