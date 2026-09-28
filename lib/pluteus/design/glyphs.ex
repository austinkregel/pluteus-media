defmodule Pluteus.Design.Glyphs do
  @moduledoc """
  The drawn glyphs (Annex A.8.6 and A.8.7), at all three of A.8.2's grids.

  A.8.7 draws fifteen because nothing in the base set's 324 serves them. These are the
  five that carry a category, which A.2.6 makes the glyph's job — colour groups by
  broad class and the glyph identifies the category within it.

  ## Each grid states its own geometry

  A.8.5 makes reduction a re-expression rather than a scaling: repeats reduce in count
  and are respaced, relative radii hold or grow, a construction serving only a
  refinement is deleted rather than shrunk, and a feature too thin to survive is
  restated as a solid region. None of that is a transform, so no grid here is derived
  from another — each says what it is, and `Pluteus.Design.Glyph` guarantees only that
  what it says is drawn the way A.8.4 requires.

  The 24 grid is stroked and the 20 and 16 grids are filled (A.8.1), so a shape that
  reads as a frame is an outline at 24 and a ribbon at the small grids, and an interior
  feature is an outline at 24 and a knockout at the small grids. A knockout is a
  subpath wound the other way, never a second overlapping shape.

  ## What a machine cannot check here

  A.8.6 names the two pairs needing most care, and both are in this set. *scan* against
  `document-text`: both are a sheet of paper, and the scanner bar crossing **beyond**
  the sheet's edges is the whole separator — the sheet keeps its folded corner at every
  grid and the bar is emphatic at 16 for that reason. *audiobook* against `book-open`:
  both are an open book, and the arc rising **clear of** the book's outer edge is the
  separator, which is why at 16 the pages become one knocked-out region and the arc
  stays outside the silhouette.

  Whether either pair is still telling apart at 16 px needs an eye. The grids, the
  viewBox, the radii and the winding are under test; recognisability is not, and
  A.8.5's own standard — "where no reduction preserves the meaning, the meaning
  changes" — is a judgement rather than a measurement.
  """

  alias Pluteus.Design.Glyph

  @doc """
  The glyphs this module draws.
  """
  @spec names() :: [String.t()]
  def names, do: ~w(audiobook comic-issue music-recording scan video-game)

  @doc """
  One glyph's parts at one grid, each named.

  Named rather than a flat list because A.8.6 rests each hard pair on a relation between
  two named parts — the bar crossing beyond the sheet, the arc clear of the book — and a
  claim about the third path in a list is a claim that breaks when a fourth is added.

  A part holds a list of paths, because a stroked grid needs its shapes apart while a
  filled grid needs a silhouette and its knockouts in one path for the winding to
  compose.
  """
  @spec parts(String.t(), pos_integer()) :: keyword([String.t()])
  def parts(name, box), do: draw(name, box)

  @doc """
  One glyph's path markup at one grid, ready to sit inside an `svg` element.

  A stroked grid needs its shapes in separate paths, because each is an outline in its
  own right. A filled grid needs them in one, because that is what makes the winding
  compose — a reversed subpath in a path of its own subtracts from nothing.
  """
  @spec paths(String.t(), pos_integer()) :: String.t()
  def paths(name, box) do
    drawings = for {_part, shapes} <- parts(name, box), shape <- shapes, do: shape

    if box == 24 do
      Enum.map_join(drawings, "", &~s(<path d="#{&1}"/>))
    else
      ~s(<path d="#{Enum.join(drawings, " ")}"/>)
    end
  end

  # ## scan — a sheet with a folded corner, crossed by a scanner bar (A.8.6)
  #
  # The bar crosses beyond both edges of the sheet, which is what separates this from
  # `document-text`. It overhangs proportionally further at 16 than at 24 because A.8.6
  # makes the bar the entire signal once the sheet has lost everything else.
  defp draw("scan", 24) do
    [
      sheet: [Glyph.sheet(6, 3, 12, 18, 1.5, 4.5, 24)],
      bar: [Glyph.bar(4.5, 13.5, 19.5, 13.5, 3, 24)]
    ]
  end

  # At the solid grids the sheet is filled and the bar is one reversed subpath across it.
  # The winding does both halves of the job: inside the sheet it subtracts to nothing, so
  # the bar is the light stripe a scanner casts, and beyond the sheet there is nothing to
  # subtract from, so the same subpath winds to minus one and fills — which under the
  # nonzero rule is a solid stub. One shape, and the crossing cannot come apart from the
  # overhang that makes it mean something.
  defp draw("scan", 20) do
    [
      sheet: [Glyph.sheet(5, 2.5, 10, 15, 1.25, 3.75, 20)],
      bar: [Glyph.bar(2.5, 11.25, 17.5, 11.25, 2.5, 20, reverse: true)]
    ]
  end

  defp draw("scan", 16) do
    [
      sheet: [Glyph.sheet(4, 2, 8, 12, 1, 3, 16)],
      bar: [Glyph.bar(2, 9, 14, 9, 2, 16, reverse: true)]
    ]
  end

  # ## music-recording — a disk: a centre hole and one groove (A.8.6)
  #
  # A.8.6 draws this rather than taking `musical-note`, because the unit a household
  # holds is a recording and a notated pitch says something about notation instead.
  #
  # The groove is deleted at 16 rather than shrunk, per A.8.5: at that grid it would be
  # three quarters of a unit of hole between two filled regions, which is the case
  # A.8.5 calls a construction serving only a refinement. The centre hole is what says
  # disk and it is kept at every grid.
  defp draw("music-recording", 24) do
    [
      disk: [Glyph.circle(12, 12, 9, 24)],
      groove: [Glyph.circle(12, 12, 5.25, 24)],
      hole: [Glyph.circle(12, 12, 1.5, 24)]
    ]
  end

  defp draw("music-recording", 20) do
    [
      disk: [
        Enum.join(
          [
            Glyph.circle(10, 10, 7.5, 20),
            Glyph.circle(10, 10, 4.5, 20, reverse: true),
            Glyph.circle(10, 10, 3.5, 20),
            Glyph.circle(10, 10, 1.75, 20, reverse: true)
          ],
          " "
        )
      ]
    ]
  end

  defp draw("music-recording", 16) do
    [
      disk: [
        Glyph.ribbon(Glyph.circle(8, 8, 6, 16), Glyph.circle(8, 8, 1.5, 16, reverse: true))
      ]
    ]
  end

  # ## comic-issue — a page of unequal panels: one wide above, two below (A.8.6)
  #
  # A.8.5's rule that a divider becomes knocked-out frames decides the whole drawing:
  # the division is the shape rather than a line that could thin away. At 24 the panels
  # are the outlines and the page is the figure they describe; at the filled grids the
  # page is the silhouette and the panels are punched out of it.
  defp draw("comic-issue", 24) do
    [
      panels: [
        Glyph.rect(3, 3, 18, 7.5, 1.5, 24),
        Glyph.rect(3, 12, 8.25, 9, 1.5, 24),
        Glyph.rect(12.75, 12, 8.25, 9, 1.5, 24)
      ]
    ]
  end

  defp draw("comic-issue", 20) do
    [
      page: [
        Enum.join(
          [
            Glyph.rect(2.5, 2.5, 15, 15, 1.5, 20),
            Glyph.rect(4, 4, 12, 5.25, 0.75, 20, reverse: true),
            Glyph.rect(4, 10.75, 5.25, 5.25, 0.75, 20, reverse: true),
            Glyph.rect(10.75, 10.75, 5.25, 5.25, 0.75, 20, reverse: true)
          ],
          " "
        )
      ]
    ]
  end

  defp draw("comic-issue", 16) do
    [
      page: [
        Enum.join(
          [
            Glyph.rect(2, 2, 12, 12, 1.25, 16),
            Glyph.rect(3.25, 3.25, 9.5, 4, 0.5, 16, reverse: true),
            Glyph.rect(3.25, 8.5, 4, 4.25, 0.5, 16, reverse: true),
            Glyph.rect(8.5, 8.5, 4.25, 4.25, 0.5, 16, reverse: true)
          ],
          " "
        )
      ]
    ]
  end

  # ## video-game — a gamepad: a body with a directional cross and two buttons (A.8.6)
  #
  # The cross is one polygon rather than two crossing bars, because two knocked-out
  # bars wind to minus one where they overlap and the centre fills back in — which
  # would leave a square with four stubs and nothing to say it had happened.
  defp draw("video-game", 24) do
    [
      body: [Glyph.rect(2.25, 7.5, 19.5, 9, 4.5, 24)],
      cross: [Glyph.plus(7.875, 12, 2.625, 0.75, 24)],
      buttons: [Glyph.circle(15.75, 10.5, 1.125, 24), Glyph.circle(18.375, 13.5, 1.125, 24)]
    ]
  end

  defp draw("video-game", 20) do
    [
      pad: [
        Enum.join(
          [
            Glyph.rect(1.75, 6.25, 16.5, 7.5, 3.75, 20),
            Glyph.plus(6.25, 10, 2.5, 0.75, 20, reverse: true),
            Glyph.circle(12.75, 8.5, 1, 20, reverse: true),
            Glyph.circle(15.5, 11.5, 1, 20, reverse: true)
          ],
          " "
        )
      ]
    ]
  end

  defp draw("video-game", 16) do
    [
      pad: [
        Enum.join(
          [
            Glyph.rect(1, 4.5, 14, 7, 3.5, 16),
            Glyph.plus(5, 8, 2.25, 0.75, 16, reverse: true),
            Glyph.circle(10.25, 6.75, 1, 16, reverse: true),
            Glyph.circle(12.5, 9.25, 1, 16, reverse: true)
          ],
          " "
        )
      ]
    ]
  end

  # ## audiobook — an open book with one sound arc rising clear of its outer edge (A.8.6)
  #
  # The arc sits outside the book's silhouette, which is the separator from `book-open`
  # and the reason it is drawn outside rather than over. At 16 the pages become one
  # knocked-out region and the arcs reduce from two to one, both A.8.5: repeats reduce
  # in count, and a feature too thin to survive is restated as a region.
  defp draw("audiobook", 24) do
    [
      book: [
        Glyph.rect(2.25, 6, 5.625, 12, 1.125, 24),
        Glyph.rect(8.625, 6, 5.625, 12, 1.125, 24)
      ],
      arcs: [
        Glyph.arc_between(14.25, 12, 3.375, -1.0472, 1.0472),
        Glyph.arc_between(14.25, 12, 6, -1.0472, 1.0472)
      ]
    ]
  end

  # At the solid grids the book is a filled silhouette with its gutter knocked out, which
  # is the base set's own construction for an open book and the reason A.8.6 says the
  # pages reduce to one knocked-out region. A hollow frame would read as a box: at 16 the
  # small grids are drawn to be read as filled shapes (A.8.2), and an outline at a solid
  # size is the thing that idiom exists to avoid.
  defp draw("audiobook", 20) do
    [
      book: [
        Glyph.rect(1.5, 5, 10, 10, 1, 20),
        Glyph.rect(5.875, 5, 1.25, 10, 0.25, 20, reverse: true)
      ],
      arcs: [
        Glyph.wave(11.5, 10, 2.75, 1.5, -0.9599, 0.9599),
        Glyph.wave(11.5, 10, 5, 1.5, -0.9599, 0.9599)
      ]
    ]
  end

  defp draw("audiobook", 16) do
    [
      book: [
        Glyph.rect(1.5, 4, 7.5, 8, 0.75, 16),
        Glyph.rect(4.625, 4, 1.25, 8, 0.25, 16, reverse: true)
      ],
      arcs: [Glyph.wave(9.25, 8, 3, 1.5, -0.9599, 0.9599)]
    ]
  end
end
