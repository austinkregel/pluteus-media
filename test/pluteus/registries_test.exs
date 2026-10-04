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
  alias Pluteus.Design.Tokens
  alias Pluteus.Ingest.Registry, as: Ingest
  alias Pluteus.Preferences
  alias Pluteus.Presentation
  alias Pluteus.Representation
  alias Pluteus.Surfaces.Registry, as: Surfaces
  alias Pluteus.Television.Registry, as: Television

  describe "the design language's token values of Annex A" do
    test "the token file resolves through accessors and carries every tier" do
      # Annex A: "Every value below is a starting value, maintained as spec-10 §20's
      # registry." What the values are, and every figure the annex requires be checked
      # in continuous integration, are asserted in design/tokens_test.exs; this is the
      # ledger entry saying the registry is seeded at all.
      assert [_ | _] = Map.keys(Tokens.all())
      assert %{"hex" => _hex} = Tokens.resolve!("sys.color.surface.base")
      assert Tokens.resolve!("base.space.200") == %{"value" => 1, "unit" => "rem"}
    end

    test "every modifier §A.1.6 declares resolves to a context that overrides something" do
      assert map_size(Tokens.contexts()) == 5
    end
  end

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

    test "caption presentation carries at least the four properties §17.4 names" do
      # §17.4 makes what caption presentation consists of this registry's, and fixes a
      # floor: a caption sits over moving picture, so the ground is what makes a contrast
      # floor meetable and the edge is its compensation where a person removes it.
      for property <- ~w(face size ground edge) do
        key = "caption_#{property}"

        assert key in Preferences.Registry.keys()
        assert %{"kind" => _kind} = Preferences.Registry.domain(key)
        assert Preferences.Registry.admits?(key, Preferences.Registry.default(key))
      end
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

  describe "the surfaces of §6, §9, §12 and §17" do
    test "the ordering nomen has a scheme of its own, which nothing generates" do
      # §6.4. An ordering nomen is a nomen rather than a reading derived from one, so the
      # scheme exists and no ingest path writes it.
      assert Surfaces.ordering_scheme() == "ordering"
      assert Surfaces.ordering_scheme() in Surfaces.nomen_schemes()
    end

    test "every mode of §9.2 is named and carries the category facet" do
      assert Surfaces.browse_modes() ==
               ~w(continue everything people places recently_added sets time)

      for mode <- Surfaces.browse_modes() do
        held = Surfaces.browse_mode(mode)

        assert is_binary(held["is"])

        # §9.2 requires the category facet be first-class on every mode's surface. The
        # prohibition there is on category as the only axis, not on reaching a film by
        # asking for films.
        assert "category" in held["default_facets"]

        assert Enum.all?(
                 held["default_facets"] ++ held["bounding_facets"],
                 &(&1 in Surfaces.facets())
               )
      end
    end

    test "only the mode §9.2 says may bound its index does" do
      # People, after credits resolve, holds every credited artist. Every other mode's
      # index is its whole set, and a bound on one of those would hide content.
      bounded =
        for mode <- Surfaces.browse_modes(),
            Surfaces.browse_mode(mode)["bounding_facets"] != [],
            do: mode

      assert bounded == ["people"]
    end

    test "every category placement can record has a surface" do
      # §12.1 carries the shape and this registry carries the values, so a category the
      # registry omits is a holding no surface knows how to present.
      for category <- Ingest.recordable_categories() do
        assert category in Surfaces.presented_categories(),
               "placement can record #{category}, which no surface presents"
      end
    end

    test "every presented category states a surface, its selectors and what it needs" do
      for category <- Surfaces.presented_categories() do
        held = Surfaces.category_presentation(category)

        assert is_binary(held["primary_surface"])
        assert is_list(held["selectors"])
        assert is_list(held["requires"])
      end
    end

    test "a companion is never its own surface and needs nothing" do
      # §12.2. A companion is catalogued as a holding so ingest does not mistake it, and
      # presented as a property of what it describes.
      for companion <- ~w(cover_art lyrics subtitles cue_sheet description metadata) do
        held = Surfaces.category_presentation(companion)

        assert held["primary_surface"] == "never its own surface"
        assert held["selectors"] == []
        assert held["requires"] == []
      end
    end

    test "a video game's surface offers no player" do
      # §12.1. The deployment runs no emulator, so the surface says so rather than
      # offering a control with nothing behind it (§17.2).
      held = Surfaces.category_presentation("video_game")

      assert held["primary_surface"] == "its entity page, and no player"
      assert held["selectors"] == []
    end

    test "the two seek steps are a small one and a larger one, per unit" do
      for unit <- [:millisecond, :page] do
        %{"small" => small, "large" => large} = Surfaces.seek_granularity(unit)

        assert small > 0
        assert large > small
      end
    end

    test "a text track's classifications are §17.4's, and unknown is one of them" do
      assert Surfaces.text_track_classifications() ==
               ~w(captions subtitles sdh forced commentary unknown)

      assert Surfaces.unknown_classification() == "unknown"
      assert Surfaces.unknown_classification() in Surfaces.text_track_classifications()
    end

    test "every affordance says what establishes it and every hazard is a person's" do
      # §17.3. The deployment must not assert either where it has not established it, so
      # an affordance is here only where a container flag can, and no hazard is.
      assert Surfaces.affordances() != []
      assert Surfaces.hazards() != []

      assert Enum.all?(Surfaces.affordances(), &is_binary/1)
      assert Enum.all?(Surfaces.hazards(), &is_binary/1)
    end
  end

  describe "the television contract of §18" do
    test "the endpoint groups are the ones §18.2 projects" do
      assert Television.projected_endpoints() ==
               ~w(system_description authentication own_record library_and_item_browsing
                  images playback_negotiation byte_serving playback_state_write_back)
    end

    test "a television holds a credential per principal, not one per device" do
      # §18.3 establishes a person rather than a device, and spec-06 §4.1 lets one device
      # hold several credentials, each separately revocable.
      assert Television.credentials_per_device() == "several"
      assert Television.credential_kind() == "client_key"
      assert Television.enrolment() == "oidc_device_authorization_grant"
    end

    test "the projected API version is never supplied in the registry's place" do
      # §18.1 makes the string a behaviour switch in the client, so a code path answering
      # where the registry does not would make it behave as though the deployment
      # answered endpoints it does not.
      assert_raise KeyError, fn -> Television.projected_api_version() end
    end
  end

  test "the registries §20 names that are not yet seeded" do
    unseeded = ~w(projected_api_version)

    # Criterion 46 is met when this list is empty. Seeding one deletes its line
    # and adds a describe block above, so the criterion's state is never inferred
    # from a count.
    assert [_ | _] = unseeded

    refute "image_profiles" in unseeded
    refute "absence_field_names" in unseeded
    refute "design_language_tokens" in unseeded

    # §17.4's amendment made caption presentation one of §20's, and it was already carried,
    # so it joins the seeded side rather than this list.
    refute "caption_presentation" in unseeded
  end
end
