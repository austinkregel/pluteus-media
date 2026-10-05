defmodule Pluteus.Design.Icons do
  @moduledoc """
  The vendored glyph set: where it lives, what is in it, and how each grid is drawn
  (Annex A.8).

  One module rather than three, because `mix icons.vendor` writes the set,
  `PluteusWeb.Icon` reads it at compile time, and `PluteusWeb.Notices` states its
  licence — and a path or a grid spelled differently in any of them is a mismatch
  nothing would report. This is the same division `Pluteus.Design.Schema` holds for
  A.1.1's vendored schemas.

  A.8.1 pins the version exactly. Raising it is editing `version/0` and re-running the
  task, so the new drawings and their digests arrive in one reviewable commit.
  """

  alias Pluteus.Design.Glyphs

  @version "2.2.0"

  @doc """
  The Heroicons release A.8.1 pins.
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Where the vendored drawings live.
  """
  @spec root() :: Path.t()
  def root, do: Application.app_dir(:pluteus, "priv/icons/heroicons")

  @doc """
  A.8.2's ladder: the name suffix that selects each grid, and the size that grid is
  drawn for.

  The suffix is what makes the band unmistakable. A glyph's rendered size is its
  drawing's own, so there is no second value for a caller to pair wrongly — which
  matters because the 20 and 16 drawings are separate artwork rather than the 24
  reduced, and below about 20 px an outline's counters close and the glyph reads as a
  grey lozenge.

  `24/solid` is absent. A.8.2 reserves it for "a filled treatment at 24 px and above
  where the surrounding design calls for one", and until something calls for one a
  template naming it should fail rather than reach a drawing nobody chose.
  """
  @spec bands() :: %{String.t() => {String.t(), String.t()}}
  def bands do
    %{
      "-micro" => {"16/solid", "size-4"},
      "-mini" => {"20/solid", "size-5"},
      "" => {"24/outline", "size-6"}
    }
  end

  @doc """
  A.8.1's table: the viewBox and the paint each grid is drawn with.

  The component emits these rather than copying a drawing's own opening tag, and the
  vendor task refuses a drawing whose tag disagrees — so a 16 grid cannot arrive under
  a 24 viewBox, which would render as a glyph in the corner of an empty box with
  nothing in the markup to say so.
  """
  @spec paint() :: %{String.t() => {String.t(), [{String.t(), String.t()}]}}
  def paint do
    %{
      "16/solid" => {"0 0 16 16", [{"fill", "currentColor"}]},
      "20/solid" => {"0 0 20 20", [{"fill", "currentColor"}]},
      "24/outline" =>
        {"0 0 24 24", [{"fill", "none"}, {"stroke", "currentColor"}, {"stroke-width", "1.5"}]}
    }
  end

  @doc """
  The glyphs this deployment names.

  Declared rather than scanned out of the templates. A.9.5 makes the vocabulary
  something a component can check a template against, and a list read from the
  templates would make it a consequence of them instead. A test asserts the two agree.

  Grouped by what warrants each name, because the warrant is what a reader needs to
  decide whether a name belongs: A.8.6's table names which categories the base set serves
  and which are drawn, §9.2 fixes the modes, and the rest is what a control on a surface
  this deployment renders cannot be drawn without.

  `document-text` and `book-open` carry a second warrant. They are the two glyphs the
  drawn set is hardest to tell from, and A.8.6 makes telling them apart at 16 px the
  review question; neither can be judged without the other in front of it.

  `previous` and `next` are absent here because they are drawn: A.8.7 draws the seek pair
  and the step pair, since a step and a scan are different commands and the base set
  gives both the same mark.
  """
  @spec inventory() :: [String.t()]
  def inventory do
    category() ++ modes() ++ transport() ++ controls()
  end

  # A.8.6's category table, wherever it names a base-set glyph rather than a drawn one.
  # The five drawn categories — music recording, audiobook, scan, comic issue and video
  # game — are `Glyphs.names/0`'s.
  defp category,
    do: ~w(film tv video-camera microphone photo document-text book-open)

  # One per mode of §9.2 the base set serves, plus the findings link §16.1 requires on
  # every surface and the switch §14.2 puts beside the principal. Continue takes `play`,
  # which the transport also names.
  defp modes,
    do: ~w(plus user map-pin clock rectangle-stack squares-2x2 exclamation-triangle
           chevron-up-down)

  # §12.3's transport. The position slider carries no glyph.
  defp transport, do: ~w(play pause queue-list)

  # What a control on a surface needs: a notice's two marks, a retry, a dismissal, the
  # sort and density controls of a narrowed surface, the verified state §16.2 renders
  # distinctly from unverified, and the one state §5.2 leaves unmarked.
  defp controls,
    do: ~w(arrow-path exclamation-circle information-circle x-mark bars-3 bars-arrow-down
           shield-check check-circle)

  @doc """
  Every vendored name, and the drawing each one resolves to.
  """
  @spec drawings() :: [{String.t(), Path.t(), String.t()}]
  def drawings do
    for glyph <- inventory(), {suffix, {grid, _dimension}} <- bands() do
      {"hero-#{glyph}#{suffix}", Path.join([root(), grid, "#{glyph}.svg"]), grid}
    end
  end

  @doc """
  Every drawn name, and the grid box each one is drawn in.

  The `hero-` prefix is not a tidiness: A.8.1 makes the vendored set's licence travel
  with the copies and with any glyph derived from them, so which artwork a template
  reaches for is something the name should say. These carry no prefix because they are
  the household's own.
  """
  @spec drawn() :: [{String.t(), String.t(), pos_integer()}]
  def drawn do
    for glyph <- Glyphs.names(), {suffix, {grid, _dimension}} <- bands() do
      {"#{glyph}#{suffix}", glyph, box(grid)}
    end
  end

  @doc """
  The grid box a grid is drawn in: 16, 20 or 24.
  """
  @spec box(String.t()) :: pos_integer()
  def box(grid), do: grid |> String.split("/") |> List.first() |> String.to_integer()

  @doc """
  Every glyph name a template may write, vendored and drawn.
  """
  @spec names() :: [String.t()]
  def names do
    vendored = Enum.map(drawings(), fn {name, _path, _grid} -> name end)
    ours = Enum.map(drawn(), fn {name, _glyph, _box} -> name end)

    Enum.sort(vendored ++ ours)
  end
end
