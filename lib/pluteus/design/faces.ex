defmodule Pluteus.Design.Faces do
  @moduledoc """
  The self-hosted faces: where they come from, what is kept of them, and where the
  vendored files live (Annex A.3.5).

  One module rather than three, for the reason `Pluteus.Design.Icons` is one: the vendor
  task writes the files, the stylesheet build emits their `@font-face` rules, and
  `PluteusWeb.Notices` states their licences. A family name or a path spelled differently
  in any of them is a mismatch nothing would report.

  **A.3.5 makes subsetting the larger saving.** Measured there, a Latin subset against an
  unsubset variable face differed roughly sevenfold — several times what variability
  saves — and it requires the subset be chosen for the coverage the household holds,
  because a catalogue's names are the worst case for it. The coverage here is Latin: over
  this library's 9586 names there are 77 distinct codepoints, 76 of them Basic Latin and
  the other a right single quote.

  A name outside that subset is still displayed rather than dropped. §6.1 selects nomens
  across languages and §6.4 forbids generating a transliteration, so spec-10 §7 expects a
  name in another script to appear; it falls to the chain in `sys.type.family.*`, which is
  what the vertical-metric override exists to keep from moving the line box.

  **Only the axes a property can reach are kept.** A.3.5 sets weight with the weight
  property and never with raw variation settings, because variation settings have no
  per-axis cascade and a utility setting one axis silently resets the others. So `wght`
  stays, `opsz` stays because A.3.5 pins optical size to the apparent size at `far`, and
  every other axis is instanced away at its default — which is most of Roboto Flex's
  thirteen.
  """

  @doc """
  Where the vendored faces live.
  """
  @spec root() :: Path.t()
  def root, do: Application.app_dir(:pluteus, "priv/fonts")

  @doc """
  Each face: the family a stylesheet names it by, the upstream it is pinned to, the axes
  kept, and the `sys.type.family` role it serves.

  `subset` is the family's own, because the two faces do different work: the interface
  face carries every name in the catalogue, and the reading face carries long-form text
  and a scan's transcript.
  """
  @spec all() :: [map()]
  def all do
    [
      %{
        id: "roboto-flex",
        family: "Roboto Flex",
        role: "sans",
        repository: "googlefonts/roboto-flex",
        version: "3.200",
        source:
          "fonts/RobotoFlex[GRAD,XOPQ,XTRA,YOPQ,YTAS,YTDE,YTFI,YTLC,YTUC,opsz,slnt,wdth,wght].ttf",
        licence: "OFL.txt",
        licence_name: "SIL Open Font License 1.1",
        keep: ~w(wght opsz),
        subset: latin()
      },
      %{
        id: "source-serif-4",
        family: "Source Serif 4",
        role: "serif",
        repository: "adobe-fonts/source-serif",
        version: "4.005R",
        source: "VAR/SourceSerif4Variable-Roman.ttf",
        licence: "LICENSE.md",
        licence_name: "SIL Open Font License 1.1",
        keep: ~w(wght opsz),
        subset: latin()
      }
    ]
  end

  @doc """
  The vendored file a face is served from, relative to `root/0`.
  """
  @spec file(map()) :: String.t()
  def file(%{id: id}), do: "#{id}.woff2"

  @doc """
  The path a stylesheet fetches a face from.

  Served by the endpoint's static plug, so it is a path under `/fonts` rather than the
  file's place on disk.
  """
  @spec served(map()) :: String.t()
  def served(face), do: "/fonts/#{file(face)}"

  @doc """
  The codepoints kept, as `pyftsubset` takes them.

  The two ranges Google Fonts publishes as `latin` and `latin-ext`, unioned. Latin alone
  would drop an accented name — a household acquires one the day it acquires a record by
  Dvořák — and the pair is what absorbs the European names a catalogue actually holds
  without reaching a second script.
  """
  @spec latin() :: String.t()
  def latin do
    Enum.join(
      [
        "U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC",
        "U+0304,U+0308,U+0329,U+2000-206F,U+2074,U+20AC,U+2122,U+2191,U+2193",
        "U+2212,U+2215,U+FEFF,U+FFFD",
        "U+0100-02BA,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,U+02DD-02FF",
        "U+1D00-1DBF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,U+20AD-20C0",
        "U+2113,U+2C60-2C7F,U+A720-A7FF"
      ],
      ","
    )
  end

  @doc """
  What the vendor task recorded: each face's own axis ranges, vertical metrics and glyph
  advances, read from the vendored file rather than declared here.

  The stylesheet's `font-weight` range, its optical-size range and the fallback's metric
  overrides all come from this, so no figure in the emitted CSS is one anybody typed.

  The advances are what A.3.4's measure is counted from. It fixes the measure at `55ch`
  and requires the character count that yields be verified by counting when the face
  changes; `ch` is the zero glyph's advance, so the count follows from the three figures
  here and `tokens_test.exs` computes it. Re-vendoring re-measures, which is what makes
  the verification hold rather than having been done once.
  """
  @spec manifest() :: map()
  def manifest do
    root() |> Path.join("SOURCES.json") |> File.read!() |> Jason.decode!()
  end

  @doc """
  The vendored licence file for a face, relative to `root/0`.

  A.8.1 requires the notice travel with the copies, so each face's own licence is
  vendored beside it and `PluteusWeb.Notices` states it. The name is prefixed with the
  face's id because the two upstreams give their licence files different names and one
  of them could as easily have given them the same.
  """
  @spec licence_file(map()) :: String.t()
  def licence_file(%{id: id, licence: licence}), do: "#{id}-#{Path.basename(licence)}"

  @doc """
  The path a face's vendored licence is read from.
  """
  @spec licence_path(map()) :: Path.t()
  def licence_path(face), do: Path.join(root(), licence_file(face))

  @doc """
  The upstream a face is vendored from.
  """
  @spec repository_url(map()) :: String.t()
  def repository_url(%{repository: repository}), do: "https://github.com/#{repository}"

  @doc """
  What a role's face is for, in the words a notice states it in.
  """
  @spec role_name(map()) :: String.t()
  def role_name(%{role: "sans"}), do: "interface face"
  def role_name(%{role: "serif"}), do: "reading face"
end
