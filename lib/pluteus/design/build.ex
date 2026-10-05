defmodule Pluteus.Design.Build do
  @moduledoc """
  Generates the interface stylesheet from the token file (Annex A.10).

  A.1.2 draws the division this rests on: "The token file is the source of truth for
  values; the build is the source of truth for expressions." Nothing here invents a
  value, and nothing in the token file carries an expression.

  A.10.1 requires three layers, in order, and the order is the whole mechanism:

  1. **Primitives in the theme layer**, where they generate utilities. Under
     Tailwind's own namespaces, so `--color-grey-03` yields `bg-grey-03` and the one
     `--spacing` base yields the entire spacing scale — which is also why A.4.1's
     "a density change is one number" needs no second token set.
  2. **Semantic and context values outside the theme layer**, on the root and on
     context scopes, so they can be rebound at runtime. This is where the five
     modifiers land, each as an attribute selector.
  3. **Semantic names registered in the theme layer as references** to those runtime
     variables, with the `inline` keyword. A.10.1: "Without it the build copies the
     value at compile time and the runtime rebinding in layer 2 silently has no
     effect. The failure mode is that the context attribute does nothing, with no
     error."

  The consequence A.10.1 states, and the reason a value is cheap to try: "one
  attribute on the document root reassigns the whole spacing scale, the whole type
  scale and the whole palette with no rebuild."

  A.10.3 settles that there is one stylesheet and not two: `far` "needs no second
  artefact and no second carrier. It is a resolver context like the other four,
  emitted into the same stylesheet." The deployment ships no client of its own, so
  there is nowhere else for a definition to go.

  A CSS variable's name is a mechanical rendering of the token's path and never a
  second vocabulary: `sys.color.border.component` becomes
  `--sys-color-border-component`. A prettier parallel name would be one more thing
  to keep in step, which is what A.1.4 and A.11 exist to prevent.
  """

  alias Pluteus.Design.Faces
  alias Pluteus.Design.Tokens

  # A.10.2: breakpoints are literal and not variables, because a custom property is
  # not a legal value in a media query condition. Tailwind substitutes these into the
  # media queries it generates, so declaring them here keeps them literal where it
  # counts. The `far` context has none — a single-column, shelf-based layout — which
  # is a layout question rather than a token one.
  @breakpoints [{"sm", "40rem"}, {"md", "48rem"}, {"lg", "64rem"}, {"xl", "80rem"}]

  # Which Tailwind namespace each primitive category belongs in, so that declaring it
  # generates utilities — A.10.1's layer 1 is explicit that primitives do. That
  # utilities exist for them is not permission to use them: A.1.4 confines templates,
  # component code and component styles to `sys`, and the lint A.1.5 requires is what
  # enforces it. A category absent here is emitted under its own path and generates
  # nothing, which is right for a value no utility should exist for.
  @namespaces %{
    "grey" => "color",
    "hue" => "color",
    "ink" => "color",
    "signal" => "color",
    "space" => "spacing"
  }

  # The media feature each context answers to, where one exists. A person who has
  # asked their system for a light theme, more contrast or less motion has already
  # said so, and the interface must honour it before any script runs — so each
  # context is emitted a second time under its query, guarded by the absence of the
  # resolved attribute. Once a script has resolved the modifier the attribute is
  # present, the query stops applying, and the recorded choice wins.
  #
  # `density` and `distance` have no media feature. There is no system signal for how
  # far away a person is sitting, which is why A.1.6 leaves both to be chosen.
  @queries %{
    {"theme", "light"} => "(prefers-color-scheme: light)",
    {"contrast", "more"} => "(prefers-contrast: more)",
    {"motion", "reduced"} => "(prefers-reduced-motion: reduce)"
  }

  # A.3.4's measure. Named here because two things about it are singular: its unit is
  # not one the format's dimension type admits, and a measure is a maximum width
  # rather than a spacing step, so it belongs in the namespace that yields `max-w-`
  # and not the one every other `sys.size` role goes to.
  @measure "sys.size.measure"

  @doc """
  The whole stylesheet, as one string.
  """
  @spec stylesheet() :: String.t()
  def stylesheet do
    [
      preamble(),
      faces(),
      primitives(),
      semantics(),
      contexts(),
      registrations()
    ]
    |> Enum.join("\n")
  end

  @doc """
  Writes the stylesheet where Tailwind's input imports it from.

  Under `assets/css/` rather than `priv/`, because Tailwind's watcher rebuilds from
  what it can see there, which is what makes editing a value a live change rather
  than a rebuild.
  """
  @spec write!() :: Path.t()
  def write! do
    target = Path.join(File.cwd!(), "assets/css/tokens.css")
    File.write!(target, stylesheet())
    target
  end

  defp preamble do
    """
    /* Generated by `mix design.build` from priv/design. Do not edit.
     *
     * spec-10 Annex A.10.1's three layers. The values are the token file's; the
     * expressions are this build's (A.1.2). Change a value in priv/design and run
     * the task again.
     */
    """
  end

  # Before the layers, because an `@font-face` is a declaration of what a family means
  # rather than a value a layer rebinds. Every figure is read from the vendored file's own
  # manifest: A.3.5's weight range, its optical-size range and the adjusted face's metrics
  # are the face's, and a figure typed here that disagreed with the file would be a layout
  # nobody could account for.
  #
  # The vendored files are committed, so a missing manifest is a broken checkout rather
  # than a state to render around: emitting no `@font-face` would leave the families
  # naming faces nothing declares, and a stylesheet that silently drops the interface's
  # type is worse than one that fails to build.
  defp faces, do: Enum.map_join(Faces.manifest()["faces"], "\n", &face/1)

  defp face(%{"axes" => axes, "metrics" => metrics} = face) do
    %{"wght" => weight, "opsz" => optical} = axes

    """
    @font-face {
      font-family: "#{face["family"]}";
      src: url("#{face["served"]}") format("woff2");
      font-weight: #{bound(weight["min"])} #{bound(weight["max"])};
      font-style: normal;
      font-display: swap;
      font-optical-sizing: auto;
      unicode-range: #{Faces.latin()};
    }

    /* A.3.5's metric-adjusted fallback: the vendored face's own vertical metrics over
     * whichever local face is present, so the line box is the same height before and
     * after the swap. The optical-size range is #{bound(optical["min"])} to #{bound(optical["max"])}.
     */
    @font-face {
      font-family: "#{face["family"]} Adjusted";
      src: #{locals(face["role"])};
      ascent-override: #{ratio(metrics["ascender"], metrics["units_per_em"])};
      descent-override: #{ratio(abs(metrics["descender"]), metrics["units_per_em"])};
      line-gap-override: #{ratio(metrics["line_gap"], metrics["units_per_em"])};
    }
    """
  end

  # The locals a role's metrics are applied over are that role's own. Adjusting a serif
  # face's metrics onto Arial would render the reading face as a sans and take precedence
  # over the Georgia that sits later in `sys.type.family.serif`, so each role names the
  # faces a desktop and the container are actually likely to hold for it.
  defp locals("sans") do
    ~s|local("Arial"), local("Helvetica Neue"), local("Liberation Sans"), local("DejaVu Sans")|
  end

  defp locals("serif") do
    ~s|local("Georgia"), local("Times New Roman"), local("Liberation Serif"), local("DejaVu Serif")|
  end

  defp ratio(value, units_per_em) do
    percentage = Float.round(value / units_per_em * 100, 2)

    if percentage == Float.round(percentage), do: "#{round(percentage)}%", else: "#{percentage}%"
  end

  # An axis bound arrives from the manifest as a float because that is what the face
  # declares; CSS takes a weight as a number, and 100.0 is not one a stylesheet should
  # carry.
  defp bound(number) when is_float(number), do: number |> round() |> Integer.to_string()
  defp bound(number) when is_integer(number), do: Integer.to_string(number)

  # Layer 1.
  defp primitives do
    declarations =
      "base"
      |> tier()
      |> Enum.map(fn {path, token} -> declaration(path, token) end)

    scale = ["", "  /* A.3.1's scale, and a line height for each of its steps. */"]

    type =
      Enum.flat_map(type_paths(), fn path ->
        name = path |> String.replace_prefix("sys.type.", "") |> String.replace(".", "-")

        [
          "  --text-#{name}: #{css(Tokens.resolve!(path))};",
          "  --text-#{name}--line-height: #{Tokens.resolve!(leading_for(path))};"
        ]
      end)

    weights =
      [
        "",
        "  /* A.3.5's weights. Tailwind's own namespace, so `font-medium` exists. */"
      ] ++
        Enum.map(~w(regular medium semibold), fn name ->
          "  --font-weight-#{name}: #{css(Tokens.resolve!("sys.weight.#{name}"))};"
        end)

    rest = [
      "",
      "  /* A.4.3's radii and A.7's easings. */",
      "  --radius-sm: #{css(Tokens.resolve!("sys.shape.radius.sm"))};",
      "  --radius-md: #{css(Tokens.resolve!("sys.shape.radius.md"))};",
      "  --radius-lg: #{css(Tokens.resolve!("sys.shape.radius.lg"))};",
      "  --radius-full: #{css(Tokens.resolve!("sys.shape.radius.full"))};",
      "  --ease-enter: #{css(Tokens.resolve!("sys.motion.easing.enter"))};",
      "  --ease-exit: #{css(Tokens.resolve!("sys.motion.easing.exit"))};",
      "  --ease-standard: #{css(Tokens.resolve!("sys.motion.easing.standard"))};",
      "",
      "  /* A.3.5's faces. */",
      "  --font-sans: #{css(Tokens.resolve!("sys.type.family.sans"))};",
      "  --font-serif: #{css(Tokens.resolve!("sys.type.family.serif"))};",
      "  --font-mono: #{css(Tokens.resolve!("sys.type.family.mono"))};",
      "",
      "  /* A.10.2: literal, because a custom property is not legal in a media",
      "   * query condition and a root-size change cannot move a rem breakpoint. */"
    ]

    breaks = Enum.map(@breakpoints, fn {name, at} -> "  --breakpoint-#{name}: #{at};" end)

    # Tailwind's own theme is cleared first, so the only names a utility can be built
    # from are the design language's. A.1.4 confines templates to `sys` and the lint
    # A.1.5 requires is what enforces that; this is why a template reaching for a
    # colour the language does not hold finds no utility to reach with.
    reset = [
      "  /* Tailwind's default theme, cleared: A.1.4 admits no third vocabulary. */",
      "  --*: initial;",
      ""
    ]

    block("@theme", reset ++ declarations ++ scale ++ type ++ weights ++ rest ++ breaks)
  end

  # Layer 2.
  defp semantics do
    declarations =
      "sys"
      |> tier()
      |> Enum.reject(fn {path, _token} -> String.starts_with?(path, "sys.type.family") end)
      |> Enum.map(fn {path, token} -> declaration(path, token) end)

    root = [
      "  /* A.3.3: the anchor the whole rem scale resolves against, and the one value",
      "   * `distance` changes to make everything else follow. In px because A.1.3",
      "   * closes its set of four on it. */",
      "  --root-size: 16px;",
      "  font-size: var(--root-size);",
      "",
      "  /* A.4.1's one base value, which Tailwind computes its whole spacing scale",
      "   * from. Held here rather than in the theme layer so that `density` rebinding",
      "   * the primitive moves the scale with it — which is what makes a density",
      "   * change one number. */",
      "  --sys-spacing-base: var(--spacing-050);",
      ""
    ]

    block(":root", root ++ declarations)
  end

  # Layer 2's context scopes. An attribute on the document root, outside the region
  # the server patches, so it survives navigation (A.10.1).
  defp contexts do
    Enum.map_join(Tokens.overrides(), "\n", fn {modifier, name} ->
      context(modifier, name) <> preference(modifier, name)
    end)
  end

  defp context(modifier, name) do
    block(~s(:root[data-#{modifier}="#{name}"]), overrides(name))
  end

  # The same context under its media feature, for a person whose system already
  # carries the preference and whose browser has no script to resolve it.
  defp preference(modifier, name) do
    case @queries[{modifier, name}] do
      nil ->
        ""

      query ->
        # A colour is two declarations in one string — the sRGB fallback then the OKLCH —
        # so the nesting is applied per line rather than per declaration.
        declarations =
          overrides(name)
          |> Enum.join("\n")
          |> String.split("\n")
          |> Enum.map_join("\n", &("  " <> &1))

        "\n@media #{query} {\n" <>
          ~s|  :root:not([data-#{modifier}]) {\n| <> declarations <> "\n  }\n}\n"
    end
  end

  defp overrides(name) do
    declarations =
      name
      |> Tokens.all()
      |> Enum.sort()
      |> Enum.map(fn {path, token} -> declaration(path, token, name) end)

    # A.3.3: `far` changes the root size, which is not a token because the anchor the
    # whole rem scale resolves against cannot itself be expressed in rem.
    extra = if name == "far", do: ["  --root-size: 32px;"], else: []

    extra ++ declarations
  end

  # Layer 3. The `inline` keyword is load-bearing: without it the value is copied at
  # compile time and layer 2's rebinding silently does nothing.
  defp registrations do
    declarations =
      "sys"
      |> tier()
      |> Enum.filter(fn {path, token} ->
        String.starts_with?(path, "sys.color.") and colour?(path, token)
      end)
      |> Enum.map(fn {path, _token} ->
        name = path |> String.replace_prefix("sys.color.", "") |> String.replace(".", "-")
        "  --color-#{name}: var(#{variable(path)});"
      end)

    spacing = [
      "",
      "  /* The spacing base, registered so Tailwind generates its scale from a value",
      "   * layer 2 can rebind. Without `inline` the build would copy it here at",
      "   * compile time and the density context would silently do nothing. */",
      "  --spacing: var(--sys-spacing-base);"
    ]

    # A.4.2's target floors and A.4.1's control height, in the namespace that gives
    # them utilities. Without this a component reaching a target floor has to write the
    # variable out by hand, and A.4.2's minimum becomes something each one remembers
    # rather than something it asks for by name.
    sizes =
      [
        "",
        "  /* A.4.2's targets and the control height, so a component asks for a floor",
        "   * by name. Registered here rather than in layer 1 because `density`",
        "   * rebinds the control height. */"
      ] ++
        Enum.map(size_paths(), fn path ->
          name = path |> String.replace_prefix("sys.size.", "") |> String.replace(".", "-")
          "  --spacing-#{name}: var(#{variable(path)});"
        end)

    # A.4.4's inset, registered so a surface's outermost element asks for its edge by
    # name. It is in layer 3 and not layer 1 because `distance` rebinds it, and the
    # whole point of the role is that the same template reaches the television's
    # figures without knowing which surface it is on.
    insets =
      [
        "",
        "  /* A.4.4's safe inset, which `distance` rebinds. */"
      ] ++
        Enum.map(space_paths(), fn path ->
          name = path |> String.replace_prefix("sys.space.", "") |> String.replace(".", "-")
          "  --spacing-#{name}: var(#{variable(path)});"
        end)

    # A measure is a maximum width, so it is registered in the namespace that yields
    # `max-w-measure` rather than among the spacing scale.
    measure = [
      "",
      "  /* A.3.4's measure, so long-form text asks for its column by name. */",
      "  --container-measure: var(#{variable(@measure)});"
    ]

    block("@theme inline", declarations ++ spacing ++ sizes ++ insets ++ measure)
  end

  defp tier(prefix) do
    Tokens.all()
    |> Enum.filter(fn {path, _token} -> String.starts_with?(path, prefix <> ".") end)
    |> Enum.sort()
  end

  defp type_paths do
    Tokens.all()
    |> Enum.map(fn {path, _token} -> path end)
    |> Enum.filter(&(String.starts_with?(&1, "sys.type.") and not family?(&1)))
    |> Enum.sort()
  end

  defp size_paths do
    Tokens.all()
    |> Enum.map(fn {path, _token} -> path end)
    |> Enum.filter(&(String.starts_with?(&1, "sys.size.") and &1 != @measure))
    |> Enum.sort()
  end

  defp space_paths do
    Tokens.all()
    |> Enum.map(fn {path, _token} -> path end)
    |> Enum.filter(&String.starts_with?(&1, "sys.space."))
    |> Enum.sort()
  end

  defp family?(path), do: String.starts_with?(path, "sys.type.family")

  defp leading_for(path), do: String.replace_prefix(path, "sys.type.", "sys.leading.")

  defp colour?(path, token), do: Tokens.typed(path, token) == "color"

  # A CSS name is a mechanical rendering of a token's path. A primitive is rendered
  # into the Tailwind namespace its category maps to, because that is what makes a
  # utility exist for it; the category stays in the name unless the namespace already
  # says it, so `base.space.200` is `--spacing-200` and `base.grey.01` is
  # `--color-grey-01`. A semantic keeps its whole path, so a reader can see which
  # token a variable came from without a table.
  @doc """
  The CSS custom property a token path is emitted as.

  A `sys` path keeps its whole path. A `base` path is rendered into the Tailwind
  namespace its category maps to.
  """
  @spec variable(String.t()) :: String.t()
  def variable("sys." <> rest), do: "--sys-" <> String.replace(rest, ".", "-")

  def variable("base." <> rest) do
    [category | tail] = String.split(rest, ".")

    case @namespaces[category] do
      nil -> "--base-" <> String.replace(rest, ".", "-")
      "spacing" -> "--spacing-" <> Enum.join(tail, "-")
      namespace -> "--#{namespace}-#{category}-" <> Enum.join(tail, "-")
    end
  end

  # One token as one or two declarations. A reference becomes a `var()` of the
  # primitive it names, which is what keeps layer 2 rebindable: rebinding the
  # primitive moves every role that points at it.
  #
  # An authored colour becomes two declarations, the sRGB fallback then the OKLCH.
  # A.2.1 requires both be authored and forbids the build computing either, so both
  # reach the stylesheet and a renderer that cannot read OKLCH keeps the first.
  defp declaration(path, token, context \\ "tokens") do
    name = variable(path)

    case token["$value"] do
      "{" <> _rest = reference ->
        "  #{name}: var(#{variable(dereference(reference))});"

      %{"colorSpace" => "oklch", "hex" => hex} = colour ->
        "  #{name}: #{hex};\n  #{name}: #{css(colour)};"

      _direct ->
        "  #{name}: #{css(Tokens.resolve!(path, context))}#{bare_unit(path)};"
    end
  end

  # A.3.4's measure is the one value in the language whose unit the format cannot carry:
  # the dimension type admits `px` and `rem` only, and a measure in `ch` is a count of
  # zero-advances rather than a distance. It is authored as that count and the unit
  # applied here, against the path rather than inferred from the type, so no other
  # number acquires a unit by being one.
  defp bare_unit(@measure), do: "ch"
  defp bare_unit(_path), do: ""

  defp dereference("{" <> rest), do: String.trim_trailing(rest, "}")

  defp css(%{"colorSpace" => "oklch", "components" => [l, c, h]}),
    do: "oklch(#{trim(l)} #{trim(c)} #{trim(h)})"

  defp css(%{"colorSpace" => _space, "hex" => hex}), do: hex
  defp css(%{"value" => value, "unit" => unit}), do: "#{trim(value)}#{unit}"
  defp css([a, b, c, d]) when is_number(a), do: "cubic-bezier(#{a}, #{b}, #{c}, #{d})"
  defp css(families) when is_list(families), do: Enum.map_join(families, ", ", &quoted/1)
  defp css(number) when is_number(number), do: trim(number)

  defp quoted(family) do
    if String.contains?(family, " ") and not String.starts_with?(family, "-"),
      do: ~s("#{family}"),
      else: family
  end

  defp trim(number) when is_float(number) do
    number |> :erlang.float_to_binary([:compact, decimals: 6]) |> String.trim_trailing(".0")
  end

  defp trim(number), do: to_string(number)

  defp block(_selector, []), do: ""

  defp block(selector, declarations) do
    "#{selector} {\n" <> Enum.join(declarations, "\n") <> "\n}\n"
  end
end
