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
  """
  @spec inventory() :: [String.t()]
  def inventory, do: ~w(arrow-path exclamation-circle information-circle play x-mark)

  @doc """
  Every name a template may write, and the drawing each one resolves to.
  """
  @spec drawings() :: [{String.t(), Path.t(), String.t()}]
  def drawings do
    for glyph <- inventory(), {suffix, {grid, _dimension}} <- bands() do
      {"hero-#{glyph}#{suffix}", Path.join([root(), grid, "#{glyph}.svg"]), grid}
    end
  end

  @doc """
  Every glyph name a template may write.
  """
  @spec names() :: [String.t()]
  def names, do: drawings() |> Enum.map(fn {name, _path, _grid} -> name end) |> Enum.sort()
end
