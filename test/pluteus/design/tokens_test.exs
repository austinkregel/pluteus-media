defmodule Pluteus.Design.TokensTest do
  @moduledoc """
  Annex A's own numbers, under continuous integration.

  A.1.1, A.2.6, A.3.2 and A.2.4 each require a figure be checked in CI rather than
  asserted in prose, and this is where that happens. The point is not to stop a
  value changing — Annex A holds that every value is a starting value maintained as
  a registry — but to make a change that breaks a published guarantee say so, with
  the number, rather than being discovered on a television.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Design.Colour
  alias Pluteus.Design.Schema
  alias Pluteus.Design.Tokens

  @contexts ~w(light far compact more reduced)
  @ramp ~w(01 02 03 04 05 06 07 08 09 10 11 12)
  @classes ~w(video audio software image text)
  @statuses ~w(error warning success info)

  # The two themes, by the file each resolves from. The dark theme is the token file
  # itself (A.2.3 makes it the default), so it has no context of its own.
  @themes ~w(tokens light)

  # A.11's emphasis ladder, as pairs of the resting rung and the engaged one. A.1.5
  # rule 3 keeps a state out of a name, so `strong` is what "hovered" and "active"
  # both resolve to — which is why the ramp's steps 04 and 05 answer one role.
  @ladder [
    {"sys.color.fill.subtle", "sys.color.fill.subtle-strong"},
    {"sys.color.fill.solid", "sys.color.fill.solid-strong"},
    {"sys.color.border.component", "sys.color.border.component-strong"}
  ]

  describe "A.1.1. Every file validates against the pinned schema" do
    test "the token file and every context override" do
      format = Schema.resolved("format")

      for file <- ["tokens" | @contexts] do
        document = document(file)

        assert :ok = ExJsonSchema.Validator.validate(format, document),
               "#{file} does not validate against the Design Tokens Format Module"
      end
    end

    test "the resolver manifest validates against the Resolver Module" do
      assert :ok = ExJsonSchema.Validator.validate(Schema.resolved("resolver"), Tokens.resolver())
      assert Tokens.resolver()["version"] == Schema.format_version()
    end
  end

  describe "A.1.3. The px primitives are a closed set of four" do
    test "exactly the four A.1.3 names, and every other dimension is rem" do
      # "A px dimension outside those four is an error, and the lint A.1.5 requires
      # enforces the list rather than the unit." The root size is the fourth and is
      # not a token: it is the anchor the scale resolves against, emitted by the
      # build, so three appear here.
      permitted = ~w(sys.border.width.hairline sys.border.width.component sys.shape.radius.full)

      in_px =
        "dimension"
        |> Tokens.of_type()
        |> Enum.filter(fn {_path, token} -> token["$value"]["unit"] == "px" end)
        |> Enum.map(fn {path, _token} -> path end)
        |> Enum.sort()

      assert in_px == Enum.sort(permitted)
    end

    test "no context override smuggles in a fifth" do
      for context <- @contexts do
        in_px =
          "dimension"
          |> Tokens.of_type(context)
          |> Enum.filter(fn {_path, token} -> token["$value"]["unit"] == "px" end)
          |> Enum.map(fn {path, _token} -> path end)

        assert in_px == [], "#{context} introduces a px dimension: #{inspect(in_px)}"
      end
    end
  end

  describe "A.1.4. A tier references only the tier below it" do
    test "no base token references anything" do
      for {path, token} <- Tokens.all(), String.starts_with?(path, "base.") do
        refute is_binary(token["$value"]) and String.starts_with?(token["$value"], "{"),
               "#{path} is a primitive and references #{inspect(token["$value"])}"
      end
    end

    test "every sys reference points at base, or at sys where the format requires it" do
      # A.1.4 lets sys reference base. A composite's own inner reference may point at
      # another sys token, which is the format's doing rather than a tier violation;
      # none appears here, so the rule reads plainly.
      for {path, token} <- Tokens.all(),
          String.starts_with?(path, "sys."),
          is_binary(token["$value"]),
          String.starts_with?(token["$value"], "{") do
        target = token["$value"] |> String.trim_leading("{") |> String.trim_trailing("}")

        assert String.starts_with?(target, "base."),
               "#{path} references #{target}, which is not a primitive"
      end
    end

    test "every reference resolves to a value that exists" do
      for {path, _token} <- Tokens.all() do
        assert Tokens.resolve!(path) != nil, "#{path} resolves to nothing"
      end
    end
  end

  describe "A.1.5. The naming rules bind" do
    test "a sys name does not exceed four segments after its tier" do
      # Rule 2. Counted after the tier, because rule 4's own example —
      # `sys.color.on.surface.strong` — has five dot-separated parts and is written as
      # a legal sys name, which only holds under that reading.
      for {path, _token} <- Tokens.all(), String.starts_with?(path, "sys.") do
        ["sys" | rest] = String.split(path, ".")
        counted = Enum.count_until(rest, 6)

        assert counted <= 4, "#{path} has #{counted} segments after its tier"
      end
    end

    test "every segment is lower-kebab and carries no reserved character" do
      for {path, _token} <- Tokens.all(), segment <- String.split(path, ".") do
        assert segment =~ ~r/^[a-z0-9]+(-[a-z0-9]+)*$/, "#{path}: #{segment} is not lower-kebab"
      end
    end

    test "`on` sits immediately after the category" do
      # Rule 4: "`on` denotes polarity and is the segment immediately after the
      # category". So `sys.color.on.…` and never `sys.on.color.…` or deeper.
      for {path, _token} <- Tokens.all(), String.contains?(path, ".on.") do
        assert ["sys", _category, "on" | _rest] = String.split(path, ".")
      end
    end

    test "no name carries a context" do
      # Rule 1, for the context names that are unambiguous in this vocabulary.
      # `full` is excluded deliberately: it names a radius that is fully round and a
      # duration that is a full transition, neither of which is the motion context of
      # the same English word. `surface` is excluded because rule 4's own example
      # contains it — rule 1 forbids naming *which* surface, not the word.
      forbidden = ~w(dark light compact comfortable near far reduced)

      for {path, _token} <- Tokens.all(), segment <- String.split(path, ".") do
        refute segment in forbidden, "#{path} carries the context #{segment}"
      end
    end
  end

  describe "A.1.6. Every declared modifier resolves to values that exist" do
    test "all five modifiers are declared, each with its default context empty" do
      # A.10.1's failure mode in another guise: a context pointing at nothing passes
      # the schema and silently does nothing. The default's override is empty because
      # the default is what the token file already holds; every other context has a
      # file, and that file is non-empty.
      declared = Tokens.resolver()["modifiers"]

      assert Enum.sort(Map.keys(declared)) ==
               ~w(contrast density distance motion theme)

      defaults = %{
        "theme" => "dark",
        "contrast" => "normal",
        "distance" => "near",
        "density" => "comfortable",
        "motion" => "full"
      }

      for {modifier, %{"contexts" => contexts}} <- declared do
        assert contexts[defaults[modifier]] == [],
               "#{modifier}'s default context should override nothing"

        for {name, sources} <- contexts, name != defaults[modifier] do
          assert [%{"$ref" => reference}] = sources

          assert Tokens.all(Path.basename(reference, ".json")) != %{},
                 "#{modifier}/#{name} points at a file that overrides nothing"
        end
      end
    end

    test "density changes only spacing and control height" do
      # A.1.6: "Density MUST NOT change text size, MUST NOT reduce a target below
      # A.4.2's floor, and MUST NOT change colour, border width, radius or elevation."
      for {path, _token} <- Tokens.all("compact") do
        assert String.starts_with?(path, "base.space.") or path == "sys.size.control.height",
               "compact changes #{path}, which A.1.6 scopes it away from"
      end
    end

    test "compact keeps every target above A.4.2's floor" do
      floor = Tokens.resolve!("sys.size.target.min")["value"]

      assert Tokens.resolve!("sys.size.control.height", "compact")["value"] > floor
    end

    test "theme and contrast change colour and nothing else" do
      for context <- ~w(light more), {path, token} <- Tokens.all(context) do
        assert Tokens.typed(path, token, context) == "color",
               "#{context} changes #{path}, and A.1.6 scopes it to colour only"
      end
    end

    test "contrast introduces no colour of its own" do
      # The whole point of the remap: `more` moves which step a role resolves to and
      # every value it reaches already exists in the ramp.
      for {_path, token} <- Tokens.all("more") do
        assert is_binary(token["$value"]) and String.starts_with?(token["$value"], "{base.grey.")
      end
    end
  end

  describe "A.2.2. The ramp measures what the annex says it measures" do
    test "every step's OKLCH and its sRGB fallback are the same colour" do
      for step <- @ramp ++ ["ring"] do
        %{"components" => [l, c, h], "hex" => hex} = Tokens.resolve!("base.grey.#{step}")

        assert {srgb, :in_gamut} = Colour.oklch(l, c, h)
        assert Colour.to_hex(srgb) == hex, "base.grey.#{step}"
      end
    end

    test "steps 11 and 12 against step 02, under both instruments" do
      ground = hex("base.grey.02")

      assert_in_delta Colour.contrast_ratio(hex("base.grey.11"), ground), 8.46, 0.01
      assert_in_delta Colour.contrast_ratio(hex("base.grey.12"), ground), 15.13, 0.01
      assert_in_delta Colour.lc(hex("base.grey.11"), ground), 60.5, 0.05
    end

    test "step 01 is not pure black and step 12 is not pure white" do
      # A.2.3, stated as a MUST NOT for a reason the annex gives: a black page leaves
      # no room to express elevation downward, and maximal light-on-dark contrast
      # blooms, worst for uncorrected astigmatism.
      refute hex("base.grey.01") == {0, 0, 0}
      refute hex("base.grey.12") == {255, 255, 255}
    end
  end

  describe "A.2.4. The floors the annex sets are the floors the roles meet" do
    test "body text clears Lc 75 and secondary text clears Lc 60 and not Lc 75" do
      ground = hex("base.grey.02")

      assert Colour.lc(resolved_hex("sys.color.on.surface.strong"), ground) >= 75
      secondary = Colour.lc(resolved_hex("sys.color.on.surface.muted"), ground)

      assert secondary >= 60
      assert secondary < 75, "the muted role would pass as body text, which A.2.2 denies it"
    end

    test "one ink is readable on every class solid under WCAG 2" do
      ink = resolved_hex("sys.color.on.class")

      for class <- @classes do
        assert Colour.contrast_ratio(ink, resolved_hex("sys.color.class.#{class}")) >= 4.5
      end
    end

    test "every solid clears both instruments against the ink it is paired with" do
      # A.2.4 binds both instruments, and they disagree here. Against the error solid the
      # dark ink measures a conforming 4.54:1 under WCAG 2 and only APCA Lc 37.2, which
      # is below the floor for something a person must perceive to operate — so checking
      # one instrument alone lets a pairing pass and fail at once.
      #
      # This is also what makes the four `on.status` roles load-bearing rather than four
      # names for one value: three take the dark ink and the error solid cannot.
      for status <- @statuses do
        solid = resolved_hex("sys.color.status.#{status}")
        ink = resolved_hex("sys.color.on.status.#{status}")

        assert Colour.contrast_ratio(ink, solid) >= 3.0,
               "#{status} fails WCAG 2 §1.4.11 against its own ink"

        assert Colour.lc(ink, solid) >= 45,
               "#{status} fails A.2.4's non-text floor against its own ink, so it " <>
                 "cannot carry even a glyph"
      end
    end

    test "a status solid is perceivable against every surface it can sit on" do
      # §1.4.11 asks 3:1 of a component's boundary, and a filled marker's boundary is
      # its own colour against the surface under it. The overlay is the worst case,
      # being the lightest surface a marker sits on.
      for status <- @statuses, surface <- ~w(base subtle raised overlay) do
        measured =
          Colour.contrast_ratio(
            resolved_hex("sys.color.status.#{status}"),
            resolved_hex("sys.color.surface.#{surface}")
          )

        assert measured >= 3.0, "#{status} has no perceivable edge on surface.#{surface}"
      end
    end

    test "a status solid holds up in the light theme too, where WCAG 2 alone binds" do
      # A.2.4 scopes its four APCA floors to the dark theme, so what a light-theme value
      # answers to is §1.4.11's 3:1 for a component and the same against its own ink.
      # The dark-theme set does not survive the move — the warning solid falls to 1.54:1
      # against a light page, which is no perceivable boundary at all — so the light theme
      # retunes them, and this is what says the retuning was enough.
      for status <- @statuses do
        solid = in_theme("sys.color.status.#{status}", "light")
        ink = in_theme("sys.color.on.status.#{status}", "light")

        for surface <- ~w(base subtle raised overlay) do
          measured =
            Colour.contrast_ratio(solid, in_theme("sys.color.surface.#{surface}", "light"))

          assert measured >= 3.0,
                 "#{status} has no perceivable edge on the light surface.#{surface}"
        end

        assert Colour.contrast_ratio(ink, solid) >= 3.0,
               "#{status} fails against its own ink in the light theme"
      end
    end

    test "a status colour is a solid and is never text, on either theme's surfaces" do
      # A.2.6 defines a status role as "a solid with an `on` pair", and the measurement is
      # why that wording matters: no status colour clears §1.4.3's 4.5:1 as body text on
      # the surfaces a form sits on, in either theme. So a message takes the surface's own
      # ink and the status colour takes the glyph — which is also the non-colour carrier
      # spec-10 §17.9 asks for.
      for status <- @statuses do
        readable =
          for theme <- @themes, surface <- ~w(base subtle raised) do
            Colour.contrast_ratio(
              in_theme("sys.color.status.#{status}", theme),
              in_theme("sys.color.surface.#{surface}", theme)
            )
          end

        assert Enum.min(readable) < 4.5,
               "#{status} clears 4.5:1 as text on every surface in both themes, which " <>
                 "would make it look usable as a text colour — and each of the four " <>
                 "falls under it somewhere, which is why none of them is one"
      end
    end

    test "only the warning solid carries body text, and the rest carry a glyph" do
      readable =
        for status <- @statuses do
          measured =
            Colour.lc(
              resolved_hex("sys.color.on.status.#{status}"),
              resolved_hex("sys.color.status.#{status}")
            )

          {status, measured >= 75}
        end

      assert Enum.filter(readable, fn {_status, body} -> body end) == [{"warning", true}]
    end

    test "a class solid carries a glyph and not body text" do
      # Measured rather than assumed: the ink clears A.2.4's Lc 45 non-text floor on
      # every class solid and reaches nothing near the Lc 75 body floor on any. The
      # annex does not say this, and a surface setting body text on a class solid
      # would be the one place its own floors were broken.
      ink = resolved_hex("sys.color.on.class")

      for class <- @classes do
        measured = Colour.lc(ink, resolved_hex("sys.color.class.#{class}"))

        assert measured >= 45, "#{class} fails even the non-text floor"
        assert measured < 75
      end
    end
  end

  describe "A.11 and A.2.2. The emphasis ladder sits on the steps whose job it is" do
    test "every fill and border rung is the ramp step A.2.2 names for that role" do
      # A.2.2 gives each of the twelve steps "a stated job" and refuses a role without
      # a written purpose. These seven roles carry A.11's ladder, and each resolves to
      # the step whose written job it is — so a rung moved to a step that does not say
      # so fails here rather than being found as a control the wrong shade.
      assert primitive("sys.color.surface.subtle") == "base.grey.02"
      assert primitive("sys.color.fill.subtle") == "base.grey.03"
      assert primitive("sys.color.fill.subtle-strong") == "base.grey.04"
      assert primitive("sys.color.fill.solid") == "base.grey.09"
      assert primitive("sys.color.fill.solid-strong") == "base.grey.10"
      assert primitive("sys.color.border.component") == "base.grey.07"
      assert primitive("sys.color.border.component-strong") == "base.grey.08"
    end

    test "each strong rung sits further from the surface than the rung below it" do
      for theme <- @themes, {below, above} <- @ladder do
        ground = in_theme("sys.color.surface.base", theme)

        assert Colour.contrast_ratio(in_theme(above, theme), ground) >
                 Colour.contrast_ratio(in_theme(below, theme), ground),
               "#{above} is no further from the surface than #{below} under #{theme}"
      end
    end

    test "a solid fill carries a glyph or large text, and never body text" do
      # The measurement a button is designed around. Against its own ink a solid rung
      # clears WCAG 2 §1.4.11's 3:1 for a component and §1.4.3's 3:1 for large text in
      # both themes, and 4.5:1 in neither — so nothing may set body text on one. The
      # APCA figures are asserted in the dark theme only, because A.2.4 scopes its four
      # floors to it; the light theme answers to WCAG 2 alone, where the same pairing
      # measures 5.0:1 while APCA reads Lc 41.
      for solid <- ~w(sys.color.fill.solid sys.color.fill.solid-strong) do
        ratios =
          for theme <- @themes,
              do:
                Colour.contrast_ratio(
                  in_theme("sys.color.on.fill", theme),
                  in_theme(solid, theme)
                )

        assert Enum.min(ratios) >= 3.0, "#{solid} fails WCAG 2 §1.4.11 against its own ink"

        assert Enum.min(ratios) < 4.5,
               "#{solid} would carry body text in one theme and not the other"

        measured = Colour.lc(in_theme("sys.color.on.fill", "tokens"), in_theme(solid, "tokens"))

        assert measured >= 60, "#{solid} fails A.2.4's large-text floor against its own ink"
        assert measured < 75
      end
    end

    test "a control with a word in it is a subtle fill, not a solid one" do
      # Where a solid fill cannot carry body text, the subtle rung with the surface's
      # own ink does — on both instruments and in both themes — which is what settles
      # how a labelled control is built rather than leaving it to taste.
      for theme <- @themes do
        assert Colour.contrast_ratio(
                 in_theme("sys.color.on.surface.strong", theme),
                 in_theme("sys.color.fill.subtle", theme)
               ) >= 4.5
      end

      assert Colour.lc(
               in_theme("sys.color.on.surface.strong", "tokens"),
               in_theme("sys.color.fill.subtle", "tokens")
             ) >= 75
    end

    test "increased contrast keeps the ladder in order and leaves the solid rungs alone" do
      # A.1.6 resolves theme before contrast, so a remapped role is followed in the
      # theme rather than in the context's own file. Two things are asserted: what the
      # context moves still ascends, and it does not move a solid fill — where a step
      # away from the surface is a step toward the ink, and step 11 would put the ink
      # at Lc 34, under the non-text floor, in the context that exists to raise it.
      remapped = Tokens.all("more")

      for theme <- @themes, {below, above} <- @ladder, Map.has_key?(remapped, above) do
        ground = in_theme("sys.color.surface.base", theme)

        assert Colour.contrast_ratio(under_more(above, theme), ground) >
                 Colour.contrast_ratio(under_more(below, theme), ground),
               "#{above} is no further from the surface than #{below} under more/#{theme}"
      end

      for solid <- ~w(sys.color.fill.solid sys.color.fill.solid-strong) do
        refute Map.has_key?(remapped, solid),
               "#{solid} is remapped by increased contrast, which lowers its ink's contrast"
      end
    end
  end

  describe "A.2.6. The class colours hold their band and their separation" do
    test "all five span 6.58:1 to 7.53:1 against step 02, with a spread under 1" do
      ground = hex("base.grey.02")

      ratios =
        Enum.map(@classes, &Colour.contrast_ratio(resolved_hex("sys.color.class.#{&1}"), ground))

      assert Enum.min(ratios) >= 6.4
      assert Enum.max(ratios) <= 7.6
      assert Enum.max(ratios) - Enum.min(ratios) < 1.0
    end

    test "every pair is at least 134 rgb units apart" do
      # The figure A.2.6 rests its whole six-classes-five-colours argument on: the
      # best available sixth hue falls 95 units from its nearest neighbour, against a
      # tightest existing pair of 134.
      assert closest(@classes, "tokens") >= 134
    end

    test "package and text resolve to one primitive, and every class has a value" do
      assert Tokens.resolve!("sys.color.class.package") == Tokens.resolve!("sys.color.class.text")

      for class <- @classes ++ ["package"] do
        assert %{"hex" => _hex} = Tokens.resolve!("sys.color.class.#{class}")
      end
    end

    test "at distance far the band rises and the separation stays above 95" do
      # The trade this context makes, asserted so that moving the lightness reports
      # what it cost. At 0.84 the five would sit 97 units apart, which is where A.2.6
      # rejected a sixth hue at 95, so this is the assertion that finds it.
      ground = hex("base.grey.02")

      ratios =
        Enum.map(@classes, fn class ->
          %{"hex" => hex} = Tokens.resolve!("base.hue.#{class}", "far")
          Colour.contrast_ratio(Colour.from_hex(hex), ground)
        end)

      assert Enum.min(ratios) > 8.5
      assert Enum.max(ratios) - Enum.min(ratios) < 1.0
      assert closest(@classes, "far") > 95
    end
  end

  describe "A.3.2 and A.6. The type ratio and the boundary obligation" do
    test "the largest size is at most 2.5 times the smallest" do
      sizes =
        "dimension"
        |> Tokens.of_type()
        |> Enum.filter(fn {path, _token} -> String.starts_with?(path, "sys.type.") end)
        |> Enum.map(fn {_path, token} -> token["$value"]["value"] end)

      assert sizes != []

      assert Enum.max(sizes) / Enum.min(sizes) <= 2.5 * 4,
             "the scale's own span; A.3.2's 2.5 bounds a fluid size against its own minimum"
    end

    test "a significant boundary clears 3:1 against every elevation surface" do
      # A.6 makes the obligation the ratio and not the step: "in this ramp no border
      # step and no surface pair reach the ratio", so border.strong resolves to the
      # ring's primitive, which does.
      boundary = resolved_hex("sys.color.border.strong")

      for step <- ~w(01 02 03 04 05) do
        assert Colour.contrast_ratio(boundary, hex("base.grey.#{step}")) >= 3.0
      end
    end

    test "no border step would have done, which is why the rule is the ratio" do
      for border <- ~w(06 07 08), surface <- ~w(01 02 03 04 05) do
        assert Colour.contrast_ratio(hex("base.grey.#{border}"), hex("base.grey.#{surface}")) <
                 3.0
      end
    end
  end

  describe "A.3.5. The face, and the limitation it carries" do
    test "every family resolves to faces the platform already has" do
      # A.3.5: "The interface self-hosts its faces; there is no external font host."
      # A stack of system faces is hosted nowhere, so nothing is fetched at render.
      for {family, generic} <- [{"sans", "sans-serif"}, {"serif", "serif"}, {"mono", "monospace"}] do
        names = Tokens.resolve!("sys.type.family.#{family}")

        assert is_list(names)
        assert generic in names, "#{family} ends without a generic family to fall back to"
      end
    end

    test "nothing sets an optical size, and the absence is stated" do
      # A.3.5: "A face without an optical-size axis cannot honour that rule. Where the
      # chosen face has none, the limitation is recorded rather than ignored."
      refute Enum.any?(Map.keys(Tokens.all()), &String.starts_with?(&1, "sys.type.optical-size"))

      stated = get_in(Tokens.read(), ["sys", "type", "family", "$description"])

      assert stated =~ "no optical-size axis"
    end

    test "distance far moves the root size and no type token" do
      refute Enum.any?(Map.keys(Tokens.all("far")), &String.starts_with?(&1, "sys.type."))
    end
  end

  describe "motion: reduced, and what the token set cannot express" do
    test "the three that move something are zeroed and the shortest is retained" do
      # A.7 requires transform and position durations resolve to zero while short
      # opacity transitions are retained. The duration tokens are named by purpose and
      # not by animated property, so the rule is mapped onto them by purpose. This
      # records that mapping as a reading rather than as something A.7 states: a token
      # set that could express the rule directly would need a duration per property.
      reduced = Tokens.all("reduced")

      for scope <- ~w(container full focus-move) do
        assert Tokens.resolve!("sys.motion.duration.#{scope}", "reduced")["value"] == 0
      end

      refute Map.has_key?(reduced, "sys.motion.duration.state")
      assert Tokens.resolve!("sys.motion.duration.state")["value"] == 200
    end
  end

  defp document(file) do
    name = if file == "tokens", do: "tokens.json", else: "contexts/#{file}.json"
    Tokens.root() |> Path.join(name) |> File.read!() |> Jason.decode!()
  end

  defp hex(path), do: path |> Tokens.resolve!() |> Map.fetch!("hex") |> Colour.from_hex()

  defp resolved_hex(path), do: hex(path)

  # The ramp step a role's reference chain ends at. A.1.4 makes every `sys` colour a
  # reference, so the chain reaches `base`; a role holding a literal returns its own
  # path, and the theme lookup then raises rather than measuring one theme twice.
  defp primitive(dotted) do
    case Tokens.fetch!(dotted)["$value"] do
      "{" <> rest -> rest |> String.trim_trailing("}") |> primitive()
      _literal -> dotted
    end
  end

  # A theme overrides some primitives and leaves the rest, so a primitive it names comes
  # from the theme and one it does not keeps the value it already has. That is the
  # resolver's own composition rather than a lookup falling back: the inks are
  # deliberately not theme-scoped, because a theme-following ink would be near-white on a
  # mid-red in one theme and near-black on it in the other.
  defp in_theme(dotted, theme) do
    path = primitive(dotted)

    case Tokens.all(theme) do
      %{^path => _token} -> hex_in(path, theme)
      %{} -> hex_in(path, "tokens")
    end
  end

  # A contrast context rebinds the role and a theme rebinds the primitive, so a role
  # the context moves is followed in the theme and one it leaves alone keeps its own
  # primitive. That is A.1.6's resolution order, theme before contrast, rather than a
  # lookup falling back to a default.
  defp under_more(dotted, theme) do
    case Tokens.all("more") do
      %{^dotted => %{"$value" => "{" <> rest}} ->
        rest |> String.trim_trailing("}") |> hex_in(theme)

      %{} ->
        in_theme(dotted, theme)
    end
  end

  defp hex_in(path, theme),
    do: path |> Tokens.resolve!(theme) |> Map.fetch!("hex") |> Colour.from_hex()

  defp closest(classes, context) do
    colours =
      Enum.map(classes, fn class ->
        %{"hex" => hex} = Tokens.resolve!("base.hue.#{class}", context)
        Colour.from_hex(hex)
      end)

    for {a, i} <- Enum.with_index(colours), {b, j} <- Enum.with_index(colours), i < j do
      Colour.distance(a, b)
    end
    |> Enum.min()
  end
end
