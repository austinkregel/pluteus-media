defmodule Pluteus.Design.Glyph do
  @moduledoc """
  The geometry a drawn glyph is built from (Annex A.8.4).

  A.8.4 gives four construction rules, and they are here as code rather than as
  guidance because three of the four are the kind of thing an eye does not catch:

  - **Radii sit on a 0.375 grid at 24 and a 0.25 grid at 20 and 16.** Every radius
    passed through here is snapped to its grid's atom, so a value off the grid cannot
    reach a path.
  - **No vertex is sharp, and the arc is authored into the path** rather than left to
    `stroke-linejoin`. A rounded join scales with the stroke and an authored arc does
    not, so the same drawing would be a different shape at each grid. `corner/3` is
    what authors them, including on a diagonal.
  - **A bar is a stadium** — a closed shape whose terminals are geometry, not a line
    with a round cap. `bar/5` is the only way to draw one and it always closes.
  - **A dot is a zero-length segment**, which renders as a dot exactly one stroke wide
    under a round cap. A small circle has its interior swallowed by its own stroke.

  ## Two renderings of one drawing

  A.8.1 draws the 24 grid as an outline and the 20 and 16 grids as solids, and A.8.5
  makes the solid form of a line figure "its stroke outlined into a ribbon of 1.5
  units, not a second drawing". So a shape that reads as a frame is a stroked outline
  at 24 and a ribbon at the small grids, and `ribbon/2` is what turns one into the
  other. A shape that reads as a mark is filled at the small grids and outlined at 24,
  which is the same path either way.

  A hole is a subpath wound the other way, which is what `reverse: true` produces.
  Winding rather than `fill-rule` because a hole inside a hole is then still a hole.

  Every number is in the grid's own units. Nothing here scales a drawing: A.8.5 makes
  reduction a re-expression, so each grid states its own geometry and this module only
  guarantees that what each states is drawn the way A.8.4 says.
  """

  # The radius atom per grid, which A.8.4 puts at about 1.5% of the box.
  @atoms %{24 => 0.375, 20 => 0.25, 16 => 0.25}

  @doc """
  The radius atom for a grid: 0.375 at 24, 0.25 at 20 and 16 (A.8.4).
  """
  @spec atom(pos_integer()) :: float()
  def atom(box), do: Map.fetch!(@atoms, box)

  @doc """
  Snaps a radius to its grid's atom.

  A.8.4 puts outer rects at 1.875 or 2.25 and interior features between 0.375 and
  0.75, all of which are multiples of the 24 grid's atom — so snapping is what makes
  those figures the only ones expressible rather than merely the recommended ones.
  """
  @spec snap(number(), pos_integer()) :: float()
  def snap(radius, box) do
    atom = atom(box)

    (radius / atom) |> Float.round() |> Kernel.*(atom) |> Float.round(4)
  end

  @doc """
  A rounded rectangle, clockwise, or counter-clockwise as a hole.
  """
  @spec rect(number(), number(), number(), number(), number(), pos_integer(), keyword()) ::
          String.t()
  def rect(x, y, width, height, radius, box, opts \\ []) do
    r = radius |> snap(box) |> min(min(width, height) / 2)

    if opts[:reverse] do
      join([
        move(x + r, y),
        arc(r, 0, x, y + r),
        line(x, y + height - r),
        arc(r, 0, x + r, y + height),
        line(x + width - r, y + height),
        arc(r, 0, x + width, y + height - r),
        line(x + width, y + r),
        arc(r, 0, x + width - r, y),
        "Z"
      ])
    else
      join([
        move(x + r, y),
        line(x + width - r, y),
        arc(r, 1, x + width, y + r),
        line(x + width, y + height - r),
        arc(r, 1, x + width - r, y + height),
        line(x + r, y + height),
        arc(r, 1, x, y + height - r),
        line(x, y + r),
        arc(r, 1, x + r, y),
        "Z"
      ])
    end
  end

  @doc """
  A circle, clockwise, or counter-clockwise as a hole.

  Two half arcs rather than four quarters, because a circle has no corner to author
  and fewer segments is fewer places for a rounding difference to show.

  Its radius is snapped like every other. A.8.4 puts every radius on the grid without
  distinguishing a corner from a circle, and the stricter reading is also the simpler
  one: one rule, no exception to remember, and a test that can check every arc in a
  drawing rather than only the ones it can tell are corners.
  """
  @spec circle(number(), number(), number(), pos_integer(), keyword()) :: String.t()
  def circle(cx, cy, radius, box, opts \\ []) do
    r = snap(radius, box)
    sweep = if opts[:reverse], do: 0, else: 1

    join([
      move(cx - r, cy),
      arc(r, sweep, cx + r, cy),
      arc(r, sweep, cx - r, cy),
      "Z"
    ])
  end

  @doc """
  A bar as a stadium: a closed shape of `thickness`, its terminals in the geometry.

  Axis-aligned only, which is every bar the inventory needs, and a stadium is then a
  rounded rectangle whose radius is half its thickness. A diagonal bar would need the
  caps rotated and nothing draws one, so it raises rather than being approximated.
  """
  @spec bar(number(), number(), number(), number(), number(), pos_integer(), keyword()) ::
          String.t()
  def bar(x1, y1, x2, y2, thickness, box, opts \\ []) do
    half = thickness / 2

    cond do
      y1 == y2 -> rect(min(x1, x2), y1 - half, abs(x2 - x1), thickness, half, box, opts)
      x1 == x2 -> rect(x1 - half, min(y1, y2), thickness, abs(y2 - y1), half, box, opts)
      true -> raise ArgumentError, "a bar is axis-aligned; nothing in A.8.7 draws a diagonal"
    end
  end

  @doc """
  A dot: a zero-length segment, which A.8.4 requires in place of a small circle.

  Under a round cap this renders as a dot exactly one stroke-width across. A circle of
  the same size has its interior swallowed by its own stroke and closes up, which is
  the failure A.8.4 names.
  """
  @spec dot(number(), number()) :: String.t()
  def dot(x, y), do: join([move(x, y), "h.008v.008h-.008Z"])

  @doc """
  The ribbon form of a closed outline: the shape itself, and the shape inset by
  `width`, wound the other way.

  A.8.5's rule for a line figure at a solid grid. The inset is taken by the caller,
  because insetting a shape is a property of that shape rather than of a ribbon — a
  rectangle insets its radius with its edges and a circle does not.
  """
  @spec ribbon(String.t(), String.t()) :: String.t()
  def ribbon(outer, inner), do: outer <> " " <> inner

  @doc """
  A rounded rectangle inset by `width`, as the inner edge of a ribbon.

  The radius shrinks with the edge so the ribbon holds one thickness all the way
  round, and never below the grid's atom — A.8.5 has relative radii hold or grow as a
  drawing shrinks, so an inner corner that tightened to a point would be the one place
  the rule was broken.
  """
  @spec inset(number(), number(), number(), number(), number(), number(), pos_integer()) ::
          String.t()
  def inset(x, y, width, height, radius, by, box) do
    rect(
      x + by,
      y + by,
      width - 2 * by,
      height - 2 * by,
      max(snap(radius, box) - by, atom(box)),
      box,
      reverse: true
    )
  end

  @doc """
  A closed polygon whose every vertex carries an authored arc.

  `points` are `{x, y, radius}` in order, and the radius is snapped to the grid. The
  turn direction at each vertex is read from the edges meeting there, so a concave
  corner arcs inward and a convex one outward with no caller saying which — which is
  what makes this the way to draw a shape with a notch in it.

  A notch is the reason this exists rather than two overlapping shapes. Two holes that
  overlap wind to minus one, which is inside under the nonzero rule, so the overlap
  fills back in: a directional cross punched as two crossing bars comes out as a
  square with four stubs. One polygon has no overlap to get wrong.
  """
  @spec polygon([{number(), number(), number()}], pos_integer(), keyword()) :: String.t()
  def polygon(points, box, opts \\ []) do
    points = if opts[:reverse], do: Enum.reverse(points), else: points
    count = length(points)

    segments =
      for {{x, y, radius}, index} <- Enum.with_index(points) do
        {px, py, _} = Enum.at(points, rem(index - 1 + count, count))
        {nx, ny, _} = Enum.at(points, rem(index + 1, count))

        {ux, uy} = unit(x - px, y - py)
        {vx, vy} = unit(nx - x, ny - y)
        r = snap(radius, box)

        # The arc is tangent to both edges, so the tangent points sit back from the
        # vertex by r·tan(δ/2), where δ is how far the direction turns.
        deviation = :math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        back = r * :math.tan(abs(deviation) / 2)
        sweep = if ux * vy - uy * vx > 0, do: 1, else: 0

        {{x - ux * back, y - uy * back}, r, sweep, {x + vx * back, y + vy * back}}
      end

    [{{fx, fy}, first_r, first_sweep, {f2x, f2y}} | rest] = segments

    # The move already sits on the first tangent point, so the first segment is its arc
    # alone — a line to where the pen already is would be a zero-length segment, which
    # A.8.4 reserves for a dot and would draw one here under a round cap.
    body =
      Enum.map_join(rest, "", fn {{ax, ay}, r, sweep, {bx, by}} ->
        line(ax, ay) <> arc(r, sweep, bx, by)
      end)

    join([move(fx, fy), arc(first_r, first_sweep, f2x, f2y), body, line(fx, fy), "Z"])
  end

  @doc """
  A sheet with one folded corner, at the top right.

  The fold introduces two 45-degree turns, and A.8.4 admits no sharp vertex, so both
  arc like every other corner — which is the whole reason this is a silhouette rather
  than a rectangle with a line drawn across it.
  """
  @spec sheet(
          number(),
          number(),
          number(),
          number(),
          number(),
          number(),
          pos_integer(),
          keyword()
        ) ::
          String.t()
  def sheet(x, y, width, height, radius, fold, box, opts \\ []) do
    a = atom(box)

    polygon(
      [
        {x, y, radius},
        {x + width - fold, y, a},
        {x + width, y + fold, a},
        {x + width, y + height, radius},
        {x, y + height, radius}
      ],
      box,
      opts
    )
  end

  @doc """
  A sheet's ribbon form: the silhouette, and the silhouette inset, wound the other way.

  Insetting a folded corner is the part worth stating. Every edge moves in by `by`, and
  the fold's diagonal moves perpendicular — so the fold's leg shrinks by `by·(2 − √2)`
  rather than by `by`, and an inner fold computed as `fold - by` would leave the
  diagonal out of parallel with the outer one.
  """
  @spec sheet_ribbon(
          number(),
          number(),
          number(),
          number(),
          number(),
          number(),
          number(),
          pos_integer()
        ) :: String.t()
  def sheet_ribbon(x, y, width, height, radius, fold, by, box) do
    ribbon(
      sheet(x, y, width, height, radius, fold, box),
      sheet(
        x + by,
        y + by,
        width - 2 * by,
        height - 2 * by,
        max(snap(radius, box) - by, atom(box)),
        fold - (2 - :math.sqrt(2)) * by,
        box,
        reverse: true
      )
    )
  end

  @doc """
  A directional cross: a plus of arm half-length `arm` and half-thickness `thickness`.

  Twelve vertices, the eight tips convex and the four inner corners concave, all
  arced. One polygon rather than two bars, for the winding reason `polygon/3` gives.
  """
  @spec plus(number(), number(), number(), number(), pos_integer(), keyword()) :: String.t()
  def plus(cx, cy, arm, thickness, box, opts \\ []) do
    t = thickness
    a = atom(box)

    polygon(
      [
        {cx - t, cy - arm, a},
        {cx + t, cy - arm, a},
        {cx + t, cy - t, a},
        {cx + arm, cy - t, a},
        {cx + arm, cy + t, a},
        {cx + t, cy + t, a},
        {cx + t, cy + arm, a},
        {cx - t, cy + arm, a},
        {cx - t, cy + t, a},
        {cx - arm, cy + t, a},
        {cx - arm, cy - t, a},
        {cx - t, cy - t, a}
      ],
      box,
      opts
    )
  end

  @doc """
  An arc of a circle, as an open stroked path.

  For a sound wave and the like, where the mark is the arc rather than a region. Only
  meaningful on the outline grid and as a ribbon at the solid grids, so a caller at a
  solid grid passes it through `wave/6` instead.
  """
  @spec arc_between(number(), number(), number(), number(), number()) :: String.t()
  def arc_between(cx, cy, r, from, to) do
    {x1, y1} = {cx + r * :math.cos(from), cy + r * :math.sin(from)}
    {x2, y2} = {cx + r * :math.cos(to), cy + r * :math.sin(to)}
    large = if abs(to - from) > :math.pi(), do: 1, else: 0

    join([move(x1, y1), "A#{n(r)} #{n(r)} 0 #{large} 1 #{n(x2)} #{n(y2)}"])
  end

  @doc """
  An arc given thickness, as a closed ribbon between two radii.

  What an arc becomes at a solid grid: A.8.5 restates a feature too thin to survive as
  a region, and an open stroked path has nothing to survive with when the grid is
  filled rather than stroked.
  """
  @spec wave(number(), number(), number(), number(), number(), number()) :: String.t()
  def wave(cx, cy, r, thickness, from, to) do
    outer = r + thickness / 2
    inner = r - thickness / 2
    {ox1, oy1} = {cx + outer * :math.cos(from), cy + outer * :math.sin(from)}
    {ox2, oy2} = {cx + outer * :math.cos(to), cy + outer * :math.sin(to)}
    {ix1, iy1} = {cx + inner * :math.cos(to), cy + inner * :math.sin(to)}
    {ix2, iy2} = {cx + inner * :math.cos(from), cy + inner * :math.sin(from)}
    cap = thickness / 2

    join([
      move(ox1, oy1),
      "A#{n(outer)} #{n(outer)} 0 0 1 #{n(ox2)} #{n(oy2)}",
      "A#{n(cap)} #{n(cap)} 0 0 1 #{n(ix1)} #{n(iy1)}",
      "A#{n(inner)} #{n(inner)} 0 0 0 #{n(ix2)} #{n(iy2)}",
      "A#{n(cap)} #{n(cap)} 0 0 1 #{n(ox1)} #{n(oy1)}",
      "Z"
    ])
  end

  defp move(x, y), do: "M#{n(x)} #{n(y)}"
  defp line(x, y), do: "L#{n(x)} #{n(y)}"
  defp arc(r, sweep, x, y), do: "A#{n(r)} #{n(r)} 0 0 #{sweep} #{n(x)} #{n(y)}"

  defp join(parts), do: Enum.join(parts)

  defp unit(dx, dy) do
    length = :math.sqrt(dx * dx + dy * dy)

    if length == 0.0,
      do: raise(ArgumentError, "a polygon has two vertices in the same place"),
      else: {dx / length, dy / length}
  end

  # Four decimals is finer than any grid here and keeps a path from carrying a float's
  # full tail, which would make two identical shapes look different in a diff.
  defp n(value) do
    rounded = Float.round(value * 1.0, 4)

    if rounded == Float.round(rounded, 0),
      do: rounded |> trunc() |> Integer.to_string(),
      else: rounded |> Float.to_string() |> String.replace_prefix("0.", ".")
  end
end
