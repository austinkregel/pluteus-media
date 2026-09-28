defmodule Pluteus.Design.Glyphs do
  @moduledoc """
  The drawn glyphs (Annex A.8.6 and A.8.7), at all three of A.8.2's grids.

  A.8.7's fifteen, drawn because nothing in the base set's 324 serves them. Five carry
  a category, which A.2.6 makes the glyph's job — colour groups by broad class and the
  glyph identifies the category within it. The rest are commands and conditions the set
  has no mark for: a step as against a scan, a seek by interval, a shuffle as against a
  swap, a repeat narrowed to one, a caption track, a described audio track, a face in a
  picture, and an integrity check that is neither passed nor failed.

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

  ## The two pairs A.8.6 says need most care

  *scan* against `document-text`: both are a sheet of paper, and the scanner bar
  crossing **beyond** the sheet's edges is the whole separator. *audiobook* against
  `book-open`: both are an open book, and the arc rising **clear of** the book's outer
  edge is the separator, which is why it sits outside the silhouette rather than over
  it.

  Both separators are geometry, and both are under test. Whether either pair still
  reads apart at 16 px is A.8.5's standard — "where no reduction preserves the meaning,
  the meaning changes" — which is a judgement and not a measurement.
  """

  alias Pluteus.Design.Glyph

  @doc """
  The glyphs this module draws.
  """
  @spec names() :: [String.t()]
  def names do
    ~w(audiobook comic-issue music-recording scan video-game) ++
      ~w(previous next back-10 forward-30 shuffle repeat-one) ++
      ~w(captions audio-description face-tag integrity-overdue)
  end

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
      # The round cap is what makes A.8.4's dot a dot: a zero-length segment renders as
      # one stroke-width across under it and as nothing without it. The base set carries
      # the same attribute on its own outline paths.
      Enum.map_join(drawings, "", &~s(<path stroke-linecap="round" d="#{&1}"/>))
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
  # Inside the sheet the winding subtracts to nothing, so the bar is the light stripe a
  # scanner casts; beyond the sheet it winds to minus one, which the nonzero rule fills,
  # so the same subpath is the solid overhang.
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
  # The cross is one polygon. Two knocked-out bars wind to minus one where they overlap,
  # which the nonzero rule fills, so the centre of a crossing pair is solid.
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
  # is A.8.6's one knocked-out region and the base set's own construction for an open
  # book. A.8.2: the small grids are drawn to be read as filled shapes.
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

  # ## previous and next — a step, which is a different command from a scan (A.8.7)
  #
  # `backward` and `forward` in the base set are scans: holding them runs the position.
  # A step moves by one, and the bar against the triangle's flat side is what says the
  # travel stops there. The two are mirrored, and mirroring is written out rather than
  # transformed, because A.8.5 makes each grid state its own geometry.
  defp draw("previous", 24) do
    [
      head: [Glyph.polygon([{7.5, 12, 1.125}, {19.5, 6, 0.75}, {19.5, 18, 0.75}], 24)],
      stop: [Glyph.bar(4.5, 6.75, 4.5, 17.25, 1.5, 24)]
    ]
  end

  defp draw("previous", 20) do
    [
      head: [Glyph.polygon([{6.25, 10, 1}, {16.25, 5, 0.5}, {16.25, 15, 0.5}], 20)],
      stop: [Glyph.bar(3.75, 5.75, 3.75, 14.25, 1.5, 20)]
    ]
  end

  defp draw("previous", 16) do
    [
      head: [Glyph.polygon([{5, 8, 0.75}, {13, 4, 0.5}, {13, 12, 0.5}], 16)],
      stop: [Glyph.bar(3, 4.75, 3, 11.25, 1.5, 16)]
    ]
  end

  defp draw("next", 24) do
    [
      head: [Glyph.polygon([{16.5, 12, 1.125}, {4.5, 18, 0.75}, {4.5, 6, 0.75}], 24)],
      stop: [Glyph.bar(19.5, 6.75, 19.5, 17.25, 1.5, 24)]
    ]
  end

  defp draw("next", 20) do
    [
      head: [Glyph.polygon([{13.75, 10, 1}, {3.75, 15, 0.5}, {3.75, 5, 0.5}], 20)],
      stop: [Glyph.bar(16.25, 5.75, 16.25, 14.25, 1.5, 20)]
    ]
  end

  defp draw("next", 16) do
    [
      head: [Glyph.polygon([{11, 8, 0.75}, {3, 12, 0.5}, {3, 4, 0.5}], 16)],
      stop: [Glyph.bar(13, 4.75, 13, 11.25, 1.5, 16)]
    ]
  end

  # ## back-10 and forward-30 — a seek by interval (A.8.7)
  #
  # A.8.5 states the loss these two take: "a two-digit numeral in a 16 box is about five
  # units tall with two counters and cannot be drawn, so below 24 px the numeral is
  # absent and the interval appears in the label and the accessible name. Direction alone
  # then separates the two controls." That is a stated loss and not a rendering fallback,
  # which is why the interval is drawn at 24 and nowhere else.
  #
  # The numerals are strokes, per A.8.4: a glyph sets no type. A one is a bar and a zero
  # is a ring; a three is two stacked arcs, which is the most a stroke can say at this
  # size and the reason no third digit would fit anywhere.
  defp draw("back-10", 24) do
    [
      loop: [Glyph.arc_between(12, 12, 8.25, 5.236, 10.472)],
      head: [Glyph.polygon([{2.625, 4.5, 0.75}, {8.25, 1.875, 0.75}, {8.25, 7.125, 0.75}], 24)],
      interval: [
        Glyph.bar(10.125, 11.25, 10.125, 15.75, 1.5, 24),
        Glyph.circle(15.375, 13.5, 2.25, 24)
      ]
    ]
  end

  defp draw("back-10", 20) do
    [
      loop: [Glyph.wave(10, 10, 6.5, 2, 5.236, 10.472)],
      head: [Glyph.polygon([{2, 4, 0.5}, {7, 1.5, 0.5}, {7, 6.5, 0.5}], 20)]
    ]
  end

  defp draw("back-10", 16) do
    [
      loop: [Glyph.wave(8, 8, 5, 2, 5.236, 10.472)],
      head: [Glyph.polygon([{1.5, 3.25, 0.5}, {5.75, 1.25, 0.5}, {5.75, 5.25, 0.5}], 16)]
    ]
  end

  defp draw("forward-30", 24) do
    [
      loop: [Glyph.arc_between(12, 12, 8.25, 5.236, 10.472)],
      head: [Glyph.polygon([{21.375, 4.5, 0.75}, {15.75, 7.125, 0.75}, {15.75, 1.875, 0.75}], 24)],
      interval: [
        Glyph.arc_between(10.5, 11.625, 1.875, -1.885, 1.885),
        Glyph.arc_between(10.5, 15, 1.875, -1.885, 1.885),
        Glyph.circle(15.75, 13.5, 2.25, 24)
      ]
    ]
  end

  defp draw("forward-30", 20) do
    [
      loop: [Glyph.wave(10, 10, 6.5, 2, 5.236, 10.472)],
      head: [Glyph.polygon([{18, 4, 0.5}, {13, 6.5, 0.5}, {13, 1.5, 0.5}], 20)]
    ]
  end

  defp draw("forward-30", 16) do
    [
      loop: [Glyph.wave(8, 8, 5, 2, 5.236, 10.472)],
      head: [Glyph.polygon([{14.5, 3.25, 0.5}, {10.25, 5.25, 0.5}, {10.25, 1.25, 0.5}], 16)]
    ]
  end

  # ## shuffle — two paths that cross (A.8.7)
  #
  # `arrows-right-left` means swap: two things change places and both still exist. A
  # shuffle is one path taking two routes, so the two bars cross rather than pass, and
  # both arrowheads point the same way.
  defp draw("shuffle", 24) do
    [
      paths: [
        Glyph.bar(3.75, 7.5, 16.5, 16.5, 1.5, 24),
        Glyph.bar(3.75, 16.5, 16.5, 7.5, 1.5, 24)
      ],
      heads: [
        Glyph.polygon([{20.25, 7.5, 0.75}, {15, 4.875, 0.75}, {15.75, 10.5, 0.75}], 24),
        Glyph.polygon([{20.25, 16.5, 0.75}, {15.75, 13.5, 0.75}, {15, 19.125, 0.75}], 24)
      ]
    ]
  end

  defp draw("shuffle", 20) do
    [
      paths: [
        Glyph.bar(3, 6.25, 13.5, 13.75, 1.5, 20),
        Glyph.bar(3, 13.75, 13.5, 6.25, 1.5, 20)
      ],
      heads: [
        Glyph.polygon([{17, 6.25, 0.5}, {12.75, 4, 0.5}, {13.25, 8.75, 0.5}], 20),
        Glyph.polygon([{17, 13.75, 0.5}, {13.25, 11.25, 0.5}, {12.75, 16, 0.5}], 20)
      ]
    ]
  end

  defp draw("shuffle", 16) do
    [
      paths: [
        Glyph.bar(2.5, 5, 10.5, 11, 1.5, 16),
        Glyph.bar(2.5, 11, 10.5, 5, 1.5, 16)
      ],
      heads: [
        Glyph.polygon([{13.5, 5, 0.5}, {10, 3.25, 0.5}, {10.5, 7, 0.5}], 16),
        Glyph.polygon([{13.5, 11, 0.5}, {10.5, 9, 0.5}, {10, 12.75, 0.5}], 16)
      ]
    ]
  end

  # ## repeat-one — a loop with a count (A.8.7)
  #
  # The rounded square is the base set's repeat-all, and keeping that silhouette is what
  # makes this read as the same command narrowed rather than as a different one. The
  # numeral is what narrows it, and a one is a single stroke, so unlike the seek
  # intervals it survives every grid — which is the whole reason this glyph can carry a
  # count and those two cannot.
  defp draw("repeat-one", 24) do
    [
      loop: [Glyph.rect(4.5, 4.5, 15, 15, 3.75, 24)],
      head: [Glyph.polygon([{19.5, 2.25, 0.75}, {19.5, 6.75, 0.75}, {15.75, 4.5, 0.75}], 24)],
      count: [Glyph.bar(12, 9.75, 12, 14.25, 1.5, 24)]
    ]
  end

  defp draw("repeat-one", 20) do
    [
      loop: [
        Glyph.rect(3.75, 3.75, 12.5, 12.5, 3, 20),
        Glyph.rect(5.25, 5.25, 9.5, 9.5, 1.5, 20, reverse: true)
      ],
      head: [Glyph.polygon([{16.25, 1.75, 0.5}, {16.25, 5.75, 0.5}, {13, 3.75, 0.5}], 20)],
      count: [Glyph.bar(10, 7.75, 10, 12.25, 1.5, 20)]
    ]
  end

  defp draw("repeat-one", 16) do
    [
      loop: [
        Glyph.rect(3, 3, 10, 10, 2.5, 16),
        Glyph.rect(4.5, 4.5, 7, 7, 1.25, 16, reverse: true)
      ],
      head: [Glyph.polygon([{13, 1.25, 0.5}, {13, 4.75, 0.5}, {10.25, 3, 0.5}], 16)],
      count: [Glyph.bar(8, 6.25, 8, 9.75, 1.5, 16)]
    ]
  end

  # ## captions — CC in a field (A.8.7)
  #
  # A.8.7: "a C is the one letterform that survives 16: an open arc with no counter".
  # Everything else about a caption track is a rectangle, so the two letters are the
  # glyph. At the filled grids they are knocked out of the field, which is the base set's
  # construction and keeps the letterform an opening rather than a stroke.
  defp draw("captions", 24) do
    [
      field: [Glyph.rect(2.25, 5.25, 19.5, 13.5, 2.25, 24)],
      letters: [
        Glyph.arc_between(9, 12, 2.625, 0.7854, 5.4978),
        Glyph.arc_between(15.75, 12, 2.625, 0.7854, 5.4978)
      ]
    ]
  end

  defp draw("captions", 20) do
    [
      field: [Glyph.rect(1.75, 4.5, 16.5, 11, 2, 20)],
      letters: [
        Glyph.wave(7.25, 10, 2.25, 1.5, 0.7854, 5.4978, reverse: true),
        Glyph.wave(13, 10, 2.25, 1.5, 0.7854, 5.4978, reverse: true)
      ]
    ]
  end

  defp draw("captions", 16) do
    [
      field: [Glyph.rect(1, 3.5, 14, 9, 1.75, 16)],
      letters: [
        Glyph.wave(5.75, 8, 2, 1.5, 0.7854, 5.4978, reverse: true),
        Glyph.wave(10.5, 8, 2, 1.5, 0.7854, 5.4978, reverse: true)
      ]
    ]
  end

  # ## audio-description — sound coming off a point inside the picture (A.8.7)
  #
  # A.8.7: an A "is two diagonals and a crossbar, three strokes in three units", so this
  # cannot be letters at all. The point is what is described and the arcs are the
  # describing, and they reduce in count at 16 rather than in weight (A.8.5).
  defp draw("audio-description", 24) do
    [
      field: [Glyph.rect(2.25, 4.5, 19.5, 15, 1.875, 24)],
      point: [Glyph.circle(8.25, 12, 1.5, 24)],
      sound: [
        Glyph.arc_between(8.25, 12, 4.5, -1.0472, 1.0472),
        Glyph.arc_between(8.25, 12, 7.125, -1.0472, 1.0472)
      ]
    ]
  end

  defp draw("audio-description", 20) do
    [
      field: [
        Glyph.rect(1.75, 3.75, 16.5, 12.5, 1.75, 20),
        Glyph.circle(6.5, 10, 1.25, 20, reverse: true),
        Glyph.wave(6.5, 10, 3.75, 1.5, -1.0472, 1.0472, reverse: true),
        Glyph.wave(6.5, 10, 6.25, 1.5, -1.0472, 1.0472, reverse: true)
      ]
    ]
  end

  defp draw("audio-description", 16) do
    [
      field: [
        Glyph.rect(1, 3, 14, 10, 1.5, 16),
        Glyph.circle(5.25, 8, 1, 16, reverse: true),
        Glyph.wave(5.25, 8, 3.5, 1.5, -1.0472, 1.0472, reverse: true)
      ]
    ]
  end

  # ## face-tag — a person in a frame, not a point (A.8.7)
  #
  # `viewfinder-circle` frames a point. What a face tag marks is a person, so the person
  # is the glyph and the frame is only what says this is a region of a picture rather
  # than a person on their own.
  defp draw("face-tag", 24) do
    [
      frame: [Glyph.rect(2.25, 2.25, 19.5, 19.5, 2.25, 24)],
      head: [Glyph.circle(12, 9.375, 2.625, 24)],
      shoulders: [Glyph.arc_between(12, 19.5, 4.875, 3.4034, 6.0214)]
    ]
  end

  defp draw("face-tag", 20) do
    [
      frame: [
        Glyph.rect(1.75, 1.75, 16.5, 16.5, 2, 20),
        Glyph.circle(10, 7.75, 2.25, 20, reverse: true),
        Glyph.wave(10, 16.25, 4.25, 1.5, 3.4034, 6.0214, reverse: true)
      ]
    ]
  end

  defp draw("face-tag", 16) do
    [
      frame: [
        Glyph.rect(1, 1, 14, 14, 1.75, 16),
        Glyph.circle(8, 6.25, 2, 16, reverse: true),
        Glyph.wave(8, 13.5, 3.75, 1.5, 3.4034, 6.0214, reverse: true)
      ]
    ]
  end

  # ## integrity-overdue — the state between checked and failed (A.8.7)
  #
  # A.8.5 settles the interior mark: the shield "leaves about four units for an interior
  # mark, a question mark is a bowl and a stem and a dot", which does not survive, "and
  # *pending* is in any case the more accurate word". So it is an ellipsis — three marks,
  # which at 24 are the zero-length segments A.8.4 reserves for a dot and at the filled
  # grids are knocked out of the shield.
  defp draw("integrity-overdue", 24) do
    [
      shield: [
        Glyph.polygon(
          [
            {12, 2.25, 1.125},
            {20.25, 5.25, 1.5},
            {20.25, 11.25, 0.375},
            {12, 21.375, 1.5},
            {3.75, 11.25, 0.375},
            {3.75, 5.25, 1.5}
          ],
          24
        )
      ],
      pending: [Glyph.dot(8.25, 10.5), Glyph.dot(12, 10.5), Glyph.dot(15.75, 10.5)]
    ]
  end

  defp draw("integrity-overdue", 20) do
    [
      shield: [
        Glyph.polygon(
          [
            {10, 1.75, 1},
            {16.75, 4.25, 1.25},
            {16.75, 9.25, 0.25},
            {10, 17.75, 1.25},
            {3.25, 9.25, 0.25},
            {3.25, 4.25, 1.25}
          ],
          20
        ),
        Glyph.circle(6.75, 8.5, 0.75, 20, reverse: true),
        Glyph.circle(10, 8.5, 0.75, 20, reverse: true),
        Glyph.circle(13.25, 8.5, 0.75, 20, reverse: true)
      ]
    ]
  end

  defp draw("integrity-overdue", 16) do
    [
      shield: [
        Glyph.polygon(
          [
            {8, 1.5, 0.75},
            {13.5, 3.5, 1},
            {13.5, 7.5, 0.25},
            {8, 14.25, 1},
            {2.5, 7.5, 0.25},
            {2.5, 3.5, 1}
          ],
          16
        ),
        Glyph.circle(5.25, 6.75, 0.75, 16, reverse: true),
        Glyph.circle(8, 6.75, 0.75, 16, reverse: true),
        Glyph.circle(10.75, 6.75, 0.75, 16, reverse: true)
      ]
    ]
  end
end
