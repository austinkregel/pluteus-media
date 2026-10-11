defmodule PluteusWeb.Icon do
  @moduledoc """
  The glyph, drawn inline from the vendored set (Annex A.8).

  A.8.1 requires icons be "inline vectors taking their colour from the text colour,
  for A.2.7's reason". The reason is that forced colours overrides `background-color`,
  so a glyph carried as a background — a masked element, which is how an icon font or a
  CSS-generated set draws one — renders as nothing for exactly the people most likely to
  be in that mode, with nothing anywhere to report it. It is the same class of failure
  as a focus ring carried only by a shadow. An inline vector painted with `currentColor`
  inherits whatever colour the mode substitutes.

  ## The drawing decides the size

  A.8.2 binds one variant to each size band, and the name's own suffix selects it, so
  `class` never sets a size: there is no pairing for a caller to get wrong because
  there is no second thing to pass. `size` reaches A.8.2's television figures, 80 px
  minimum and 96 preferred, and only the 24 grid admits them — a 56 px glyph at three
  metres subtends 41 arcminutes, optically a 22 px browser icon, so ordered by what the
  eye receives the television sits with the small icons while taking the largest
  drawing.

  ## The vocabulary is what is vendored

  The names come from `Pluteus.Design.Icons`, and the drawings are read at compile time
  from what `mix icons.vendor` wrote. So the set that exists is the set a template may
  name, which closes A.9.5 twice: a literal name outside it fails to compile, and a
  name arriving as a value raises at the call site.
  """
  use Phoenix.Component

  alias Pluteus.Design.Glyphs
  alias Pluteus.Design.Icons

  # The vendored vocabulary is what is on disk, not what `Icons.inventory/0` declares.
  # The two must agree and a test says so, but the dependency has to run this way round:
  # the vendor task compiles the app before it fetches anything, so a module that
  # insisted on a declared name would refuse to compile until the file existed and the
  # task could never be the thing that put it there.
  #
  # Read at compile time so rendering is no file read, and registered as external
  # resources so re-vendoring recompiles this module.
  @paths (for {suffix, {grid, _dimension}} <- Icons.bands(),
              path <- Path.wildcard(Path.join([Icons.root(), grid, "*.svg"])) do
            {"hero-" <> Path.basename(path, ".svg") <> suffix, path, grid}
          end)

  for {_name, path, _grid} <- @paths do
    @external_resource path
  end

  # The wildcard above is evaluated once, so a drawing added since this module was last
  # compiled matches nothing and registers no resource of its own: a glyph vendored
  # after the fact would be absent from the vocabulary with nothing to say so. The
  # manifest is rewritten by every run of the vendor task, so depending on it is what
  # makes a new drawing recompile this module rather than needing to be remembered.
  @external_resource Path.join(Icons.root(), "SOURCES.json")

  @vendored (for {name, path, grid} <- @paths, into: %{} do
               {view_box, paint} = Map.fetch!(Icons.paint(), grid)
               [_opening, rest] = String.split(File.read!(path), ">", parts: 2)
               inner = rest |> String.trim() |> String.trim_trailing("</svg>") |> String.trim()

               {name, %{inner: inner, view_box: view_box, paint: paint}}
             end)

  # The drawn set has no files: A.8.5 makes each grid its own geometry rather than a
  # transform of another, so the geometry is the artefact and a generated file beside it
  # would be a second copy to keep in step.
  @ours (for {name, glyph, box} <- Icons.drawn(), into: %{} do
           grid = if box == 24, do: "24/outline", else: "#{box}/solid"
           {view_box, paint} = Map.fetch!(Icons.paint(), grid)

           {name, %{inner: Glyphs.paths(glyph, box), view_box: view_box, paint: paint}}
         end)

  @glyphs Map.merge(@vendored, @ours)

  @names @glyphs |> Map.keys() |> Enum.sort()

  @doc """
  Every glyph name a template may write.
  """
  @spec names() :: [String.t()]
  def names, do: @names

  @doc """
  Renders a glyph at the size its own grid is drawn for.

  ## Examples

      <.icon name="hero-x-mark-mini" />
      <.icon name="hero-arrow-path-micro" class="ml-1 motion-safe:animate-spin" />
      <.icon name="hero-play" size={96} />
  """
  attr :name, :string, required: true, values: @names
  attr :size, :integer, default: nil, values: [nil, 80, 96]
  attr :class, :any, default: nil
  attr :rest, :global

  def icon(assigns) do
    assigns =
      assign(assigns,
        glyph: Map.fetch!(@glyphs, assigns.name),
        dimension: dimension(assigns.name, assigns.size)
      )

    ~H"""
    <svg
      class={[@dimension, @class]}
      viewBox={@glyph.view_box}
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
      {@glyph.paint}
      {@rest}
    >
      {Phoenix.HTML.raw(@glyph.inner)}
    </svg>
    """
  end

  # The band the name selects, by its suffix. Longest suffix first, since a bare name is
  # the 24 outline and every other band adds to it.
  defp dimension(name, nil) do
    {_suffix, {_grid, size}} =
      Icons.bands()
      |> Enum.sort_by(fn {suffix, _band} -> -String.length(suffix) end)
      |> Enum.find(fn {suffix, _band} -> String.ends_with?(name, suffix) end)

    size
  end

  defp dimension(name, large) when large in [80, 96] do
    if dimension(name, nil) != "size-6" do
      raise ArgumentError,
            "#{name} is a small grid and does not reach #{large}px (A.8.2): " <>
              "the television takes the 24 outline, which is the name without a suffix"
    end

    if large == 80, do: "size-20", else: "size-24"
  end
end
