defmodule Pluteus.Continuity.RegistryTest do
  @moduledoc """
  The continuity values spec-10 §20 holds, which spec-10 §13.2's thresholds and
  §13.3's conflict rule read.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Catalog.Extent
  alias Pluteus.Continuity.Registry

  @regimes ~w(proportional absolute none)

  test "every category the registry names declares a known regime" do
    for {category, threshold} <- thresholds() do
      assert threshold["regime"] in @regimes, "#{category} declares no known regime"
    end
  end

  describe "the floor and ceiling are proportions for short media and quantities for long" do
    test "a proportional category carries a floor and a ceiling between nothing and everything" do
      for {category, %{"regime" => "proportional"} = threshold} <- thresholds() do
        assert threshold["floor"] > 0, "#{category}'s floor discards nothing"
        assert threshold["ceiling"] < 1, "#{category}'s ceiling is never reached"
        assert threshold["floor"] < threshold["ceiling"]
      end
    end

    test "an absolute category states its ceiling as the time remaining" do
      for {category, %{"regime" => "absolute"} = threshold} <- thresholds() do
        assert is_integer(threshold["floor_ms"]), "#{category} has no absolute floor"

        assert is_integer(threshold["ceiling_remaining_ms"]),
               "#{category}'s ceiling is not expressed as time remaining"
      end
    end

    test "a long category is absolute, because a proportion of a long work is not small" do
      for category <- ~w(film television_episode audiobook podcast_episode) do
        assert Registry.resume_threshold(category)["regime"] == "absolute"
      end
    end

    test "every category that keeps a position states a minimum length" do
      for {category, threshold} <- thresholds(), threshold["regime"] != "none" do
        assert threshold["minimum_length_ms"] || threshold["minimum_length_pages"],
               "#{category} keeps a position for a thing of any length"
      end
    end
  end

  describe "a category that is looked at rather than got part way through keeps none" do
    test "a photograph, a scan and a game keep no position" do
      refute Registry.keeps_position?("photograph")
      refute Registry.keeps_position?("scan")
      refute Registry.keeps_position?("video_game")
    end

    test "a recording, a film and a book do" do
      assert Registry.keeps_position?("music_recording")
      assert Registry.keeps_position?("film")
      assert Registry.keeps_position?("ebook")
      assert Registry.keeps_position?("comic_issue")
    end

    test "a companion kind keeps none" do
      for kind <- ~w(cover_art lyrics subtitles cue_sheet description metadata) do
        refute Registry.keeps_position?(kind), "#{kind} keeps a resume position"
      end
    end
  end

  test "a category the registry does not name raises rather than keeping a position for it" do
    assert_raise KeyError, fn -> Registry.resume_threshold("hologram") end
    assert_raise KeyError, fn -> Registry.keeps_position?("hologram") end
  end

  test "the reporting interval is what §13.3's idle rule is measured against" do
    assert is_integer(Registry.reporting_interval_ms())
    assert Registry.reporting_interval_ms() > 0
  end

  describe "how far a resume may move backwards before it must be stated" do
    test "every unit a selector counts in carries a threshold" do
      for unit <- Extent.units() do
        assert is_number(Registry.backwards_threshold(unit)),
               "#{unit} has no backwards threshold"
      end
    end

    test "a unit the registry does not name raises" do
      assert_raise KeyError, fn -> Registry.backwards_threshold(:furlong) end
    end
  end

  test "a shared surface returns to the choice of principal after a stated period" do
    assert is_integer(Registry.inactivity_period_ms())

    # Long enough not to interrupt a film, short enough that the next person does
    # not inherit the last one's identity.
    assert Registry.inactivity_period_ms() > Registry.reporting_interval_ms()
  end

  defp thresholds do
    for category <- Registry.categories(), into: %{} do
      {category, Registry.resume_threshold(category)}
    end
  end
end
