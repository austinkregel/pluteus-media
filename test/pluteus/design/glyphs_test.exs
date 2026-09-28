defmodule Pluteus.Design.GlyphsTest do
  @moduledoc """
  Annex A.8.4's construction and A.8.6's two hard separators, as far as either can be
  checked without an eye.

  A.8.5 is explicit that the rest cannot be: "where no reduction preserves the meaning,
  the meaning changes", which is a judgement. So what is asserted here is what a machine
  can settle — the grid a radius sits on, that a drawing stays inside its box, that a dot
  is a zero-length segment rather than a circle, and that the one geometric fact A.8.6
  rests each hard pair on actually holds at every grid.

  A.8.6 names those two pairs. *scan* against a document: both are a sheet, and the
  scanner bar crossing **beyond** the sheet's edges is the whole separator. *audiobook*
  against an ebook: both are an open book, and the arc rising **clear of** the book's
  outer edge is the separator. Each is a statement about coordinates, so each is a test.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Design.Glyph
  alias Pluteus.Design.Glyphs

  @grids [24, 20, 16]

  describe "A.8.4. Radii sit on the grid, and nothing else can reach a path" do
    test "a radius off the grid is snapped to it" do
      # 0.375 at 24 and 0.25 at 20 and 16, which is about 1.5% of the box. A.8.4's own
      # figures — 1.875 and 2.25 for an outer rect, 0.375 to 0.75 for an interior feature
      # — are all multiples of the 24 atom, so snapping is what makes them the only
      # values expressible rather than the recommended ones.
      assert Glyph.snap(2.2, 24) == 2.25
      assert Glyph.snap(1.9, 24) == 1.875
      assert Glyph.snap(0.4, 24) == 0.375
      assert Glyph.snap(1.2, 20) == 1.25
      assert Glyph.snap(0.6, 16) == 0.5
    end

    test "every corner radius in a drawing is a multiple of its grid's atom" do
      # Snapping happens inside the geometry, so this is the assertion that no drawing
      # reaches a path by another route — a hand-written path string among the generated
      # ones would fail here.
      for name <- Glyphs.names(),
          box <- @grids,
          {part, drawings} <- Glyphs.parts(name, box),
          data <- drawings,
          radius <- radii(data) do
        atom = Glyph.atom(box)

        assert_in_delta Float.round(radius / atom) * atom,
                        radius,
                        0.0001,
                        "#{name}'s #{part} at #{box} has a radius of #{radius}, " <>
                          "off the #{atom} grid"
      end
    end

    test "a dot is a zero-length segment and no drawing uses a circle element" do
      # A.8.4: a small circle has its interior swallowed by its own stroke and closes up,
      # so the dot is `h.008v.008h-.008Z` under a round cap instead.
      assert Glyph.dot(4, 4) == "M4 4h.008v.008h-.008Z"

      for name <- Glyphs.names(), box <- @grids do
        refute Glyphs.paths(name, box) =~ "<circle"
      end
    end

    test "a bar is axis-aligned, because a diagonal stadium is not drawn" do
      assert_raise ArgumentError, fn -> Glyph.bar(0, 0, 4, 4, 1, 24) end
    end

    test "a polygon opens on its first arc, not on a zero-length line" do
      # The move already sits on the first tangent point. A line to where the pen is would
      # be a zero-length segment, which under a round cap draws the dot A.8.4 reserves it
      # for — a stray dot at one corner of every polygon.
      path = Glyph.plus(12, 12, 3, 1, 24)

      refute path =~ ~r/^M([\d.]+) ([\d.]+)L\1 \2/
      assert path =~ ~r/^M[\d.]+ [\d.]+A/
    end
  end

  describe "A.8.1 and A.8.5. Three grids, each stating its own geometry" do
    test "every glyph is drawn at all three grids" do
      for name <- Glyphs.names(), box <- @grids do
        assert Glyphs.paths(name, box) =~ "<path d=\""
      end
    end

    test "a drawing stays inside its own box" do
      for name <- Glyphs.names(), box <- @grids, {part, drawings} <- Glyphs.parts(name, box) do
        points = Enum.flat_map(drawings, &endpoints/1)
        {low, high} = Enum.min_max(Enum.flat_map(points, &Tuple.to_list/1))

        assert low >= 0, "#{name}'s #{part} at #{box} reaches #{low}, outside its box"
        assert high <= box, "#{name}'s #{part} at #{box} reaches #{high}, outside its box"
      end
    end

    test "no grid is a scaled copy of another" do
      # A.8.5 makes reduction a re-expression: repeats reduce in count and are respaced,
      # and a construction serving only a refinement is deleted. A drawing that scaled
      # would have the same path count at every grid and the same shape in each.
      for name <- Glyphs.names() do
        shapes = Enum.map(@grids, fn box -> Glyphs.paths(name, box) end)

        assert Enum.uniq(shapes) == shapes, "#{name} repeats a drawing across grids"
      end
    end

    test "the disk drops its groove at 16 rather than shrinking it" do
      # A.8.5's rule for a construction serving only a refinement. At 16 the groove would
      # be three quarters of a unit of hole between two filled regions; the centre hole is
      # what says disk, and it is kept at every grid.
      assert Keyword.has_key?(Glyphs.parts("music-recording", 24), :groove)
      refute Keyword.has_key?(Glyphs.parts("music-recording", 16), :groove)

      # The hole survives all three, whether as its own part at 24 or as a knockout in the
      # disk below it, which is what the count of distinct radii records.
      assert concentric("music-recording", 24) == 3
      assert concentric("music-recording", 20) == 4
      assert concentric("music-recording", 16) == 2
    end
  end

  describe "A.8.6. The separator each hard pair rests on" do
    test "the scanner bar crosses beyond the sheet at every grid" do
      # The whole of what separates a scan from a document. A.8.6: the sheet keeps its
      # folded corner at every grid and loses its text lines, so the bar is the entire
      # signal — and a bar that stopped at the sheet's edge would leave the two glyphs
      # identical.
      for box <- @grids do
        parts = Glyphs.parts("scan", box)

        {sheet_left, sheet_right} = span(parts[:sheet], :x)
        {bar_left, bar_right} = span(parts[:bar], :x)

        assert bar_left < sheet_left,
               "at #{box} the bar starts at #{bar_left}, inside the sheet's #{sheet_left}"

        assert bar_right > sheet_right,
               "at #{box} the bar ends at #{bar_right}, inside the sheet's #{sheet_right}"
      end
    end

    test "the sound arc rises clear of the book's outer edge at every grid" do
      # The same problem and the same answer for an audiobook against an ebook. A.8.6 puts
      # the signal outside the silhouette on purpose, so that at 16 — where the pages
      # become one knocked-out region — the part that distinguishes them is the part that
      # is not the book.
      for box <- @grids do
        parts = Glyphs.parts("audiobook", box)
        {_left, book_right} = span(parts[:book], :x)

        for arc <- parts[:arcs] do
          {arc_left, _right} = span([arc], :x)

          assert arc_left > book_right,
                 "at #{box} an arc starts at #{arc_left}, over the book's edge at #{book_right}"
        end
      end
    end

    test "the arcs reduce in count at 16, where the pages become one region" do
      # A.8.6 for this glyph, stated as counts: two arcs above 16 and one at it, because
      # repeats reduce in count rather than in weight.
      assert [_outer, _inner] = Glyphs.parts("audiobook", 24)[:arcs]
      assert [_outer, _inner] = Glyphs.parts("audiobook", 20)[:arcs]
      assert [_only] = Glyphs.parts("audiobook", 16)[:arcs]
    end
  end

  defp span(drawings, :x) do
    drawings |> Enum.flat_map(&endpoints/1) |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
  end

  # Concentric circles in one glyph, counted by distinct arc radius — which is what the
  # disk's construction is: a filled circle with rings knocked out of it.
  defp concentric(name, box) do
    for {_part, drawings} <- Glyphs.parts(name, box), data <- drawings, radius <- radii(data) do
      radius
    end
    |> Enum.uniq()
    |> length()
  end

  # Every point a path's pen lands on. An arc may bulge slightly past its endpoints, so
  # this is a bound on the vertices rather than on the rendered shape — which is the right
  # measure for both of A.8.6's separators, since each is a statement about where a
  # drawing's edges are.
  defp endpoints(data) do
    data
    |> tokens()
    |> Enum.reduce({[], {0.0, 0.0}}, fn
      {"M", [x, y]}, {found, _at} ->
        {[{x, y} | found], {x, y}}

      {"L", [x, y]}, {found, _at} ->
        {[{x, y} | found], {x, y}}

      {"A", args}, {found, _at} ->
        point = Enum.take(args, -2) |> List.to_tuple()
        {[point | found], point}

      {"h", [dx]}, {found, {x, y}} ->
        {[{x + dx, y} | found], {x + dx, y}}

      {"v", [dy]}, {found, {x, y}} ->
        {[{x, y + dy} | found], {x, y + dy}}

      {"Z", []}, state ->
        state
    end)
    |> elem(0)
  end

  # An arc's radii are its first two arguments, and this geometry only ever draws circular
  # arcs, so the two agree and one of them is the radius.
  defp radii(data) do
    for {"A", [rx, _ry | _rest]} <- tokens(data), do: rx
  end

  defp tokens(data) do
    Regex.scan(~r/([MLAZhv])([^MLAZhv]*)/, data, capture: :all_but_first)
    |> Enum.map(fn [command, args] -> {command, numbers(args)} end)
  end

  defp numbers(text) do
    Regex.scan(~r/-?(?:\d+\.\d+|\d+|\.\d+)/, text)
    |> List.flatten()
    |> Enum.map(fn token ->
      token |> String.replace(~r/^(-?)\./, "\\g{1}0.") |> Float.parse() |> elem(0)
    end)
  end
end
