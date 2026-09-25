defmodule Pluteus.RegistriesTest do
  @moduledoc """
  spec-10 criterion 46: every registry §20 names is populated, and no code path
  supplies a value a registry omits.

  §20 names twenty registries across five groups. This file asserts each seeded
  one resolves through an accessor rather than merely existing in a file, and
  names the ones that do not yet, so the criterion's state is readable in one
  place.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Catalog.Extent
  alias Pluteus.Continuity
  alias Pluteus.Presentation
  alias Pluteus.Representation

  describe "the presentation profiles of §11" do
    test "image profiles are populated" do
      assert [_ | _] = Presentation.Registry.image_profiles()
      assert Presentation.Registry.default_image_profile()["width"] > 0
    end

    test "the tiling threshold is populated" do
      assert Presentation.Registry.tiling()["threshold_pixels"] > 0
      assert Presentation.Registry.tiling()["tile_size"] > 0
    end

    test "the trickplay profile is populated" do
      trickplay = Presentation.Registry.trickplay()

      assert trickplay["frame_interval_ms"] > 0
      assert trickplay["tile_columns"] * trickplay["tile_rows"] > 0
    end

    test "the waveform profiles are populated" do
      assert Presentation.Registry.waveform_overview()["points"] > 0
      assert [_ | _] = Presentation.Registry.waveform_detail()
    end

    test "the key frame position is populated" do
      assert Presentation.Registry.key_frame()["proportion"] > 0
    end
  end

  describe "the continuity values of §13" do
    test "resume thresholds are populated" do
      assert [_ | _] = Continuity.Registry.categories()
    end

    test "the reporting interval is populated" do
      assert Continuity.Registry.reporting_interval_ms() > 0
    end

    test "the backwards threshold is populated for every unit a selector counts in" do
      for unit <- Extent.units() do
        assert Continuity.Registry.backwards_threshold(unit) > 0
      end
    end

    test "the inactivity period is populated" do
      assert Continuity.Registry.inactivity_period_ms() > 0
    end
  end

  describe "the presentation vocabularies of §6, §9, §12 and §17" do
    test "the absence field names spec-02 §6.5 requires are populated" do
      assert [_ | _] = Representation.Registry.absence_fields()
    end
  end

  test "no code path supplies a value a registry omits" do
    # Each accessor that answers per key raises rather than returning nil, so a
    # caller cannot proceed on a value the seed does not hold.
    assert_raise KeyError, fn -> Presentation.Registry.assumed_aspect_ratio("hologram") end
    assert_raise KeyError, fn -> Continuity.Registry.resume_threshold("hologram") end
    assert_raise KeyError, fn -> Continuity.Registry.backwards_threshold(:furlong) end
    assert_raise KeyError, fn -> Representation.Registry.kinds_of("mood") end
  end

  test "the registries §20 names that are not yet seeded" do
    unseeded = ~w(
      nomen_schemes
      browse_modes
      category_presentation
      seek_granularities
      text_track_classifications
      accessibility_affordances_and_hazards
      projected_api_version
      projected_endpoints
      credential_policy
      design_language_tokens
    )

    # Criterion 46 is met when this list is empty. Seeding one deletes its line
    # and adds a describe block above, so the criterion's state is never inferred
    # from a count.
    assert [_ | _] = unseeded

    refute "image_profiles" in unseeded
    refute "absence_field_names" in unseeded
  end
end
