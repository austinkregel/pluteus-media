defmodule PluteusWeb.Surfaces.Pages do
  @moduledoc """
  The page reader: the surface a comic issue is read on ([spec-10] §12.1).

  One page at a time, each a graded width of the archive's own entry, offered at every
  width §20 holds so that a browser takes the one its own pixels ask for (§11.1).

  §12.3's position is counted in pages, which is the unit §20 holds this medium's seek
  granularity in and the unit placement measured the holding in — so the slider runs
  over what the catalogue says is there rather than over what has been made so far, and
  a page that is not there yet is still a page a person can turn to.

  §11.2's box is reserved before the page arrives, at the shape a width of that page was
  measured in where one has been made and §20's figure for the category where none has.
  A page nobody has made yet, one a tool tried and could not read, and a holding with no
  bytes to make one from are three different facts (§5.2), and none of them is a failure
  of this surface (§11.6).
  """

  use PluteusWeb, :html

  alias Pluteus.Surfaces.Registry, as: Surfaces
  alias PluteusWeb.Surfaces.Medium

  attr :name, :string, required: true
  attr :category, :string, required: true
  attr :borne, :any, required: true
  attr :page, :integer, required: true
  attr :pages, :any, required: true
  attr :shown, :any, required: true
  attr :reserved, :any, default: nil

  def surface(assigns) do
    ~H"""
    <div class="flex min-h-0 w-full flex-1 flex-col">
      <Medium.band name={@name} category={@category} />

      <.turnable
        shown={@shown}
        name={@name}
        borne={@borne}
        page={@page}
        pages={@pages}
        reserved={@reserved}
      />
    </div>
    """
  end

  attr :shown, :any, required: true
  attr :name, :string, required: true
  attr :borne, :any, required: true
  attr :page, :integer, required: true
  attr :pages, :any, required: true
  attr :reserved, :any, required: true

  defp turnable(%{pages: pages} = assigns) when is_integer(pages) and pages > 0 do
    ~H"""
    <div class="flex min-h-0 flex-1 flex-col">
      <div class="flex flex-1 items-start justify-center overflow-y-auto p-4 sm:p-6">
        <.page shown={@shown} name={@name} borne={@borne} page={@page} reserved={@reserved} />
      </div>

      <.position page={@page} pages={@pages} />
    </div>
    """
  end

  defp turnable(assigns) do
    assigns = assign(assigns, :said, nothing(assigns.borne, assigns.pages))

    ~H"""
    <div class="mx-auto max-w-measure px-4 py-10 sm:px-6">
      <p id="page-absence" class="text-body-md text-on-surface-muted">{@said}</p>
    </div>
    """
  end

  # Why there is no page to turn to, which is three different facts: the household holds
  # no file for this, it holds one and nothing has counted what is in it, or it counted
  # and found none.
  defp nothing(nil, _pages), do: "No file is held for this, so there is no page to turn to."

  defp nothing(_borne, nil),
    do: "Nothing has counted the pages of this, so there is no page to turn to."

  defp nothing(_borne, 0), do: "No pages were counted in this, so there is nothing to turn to."

  attr :shown, :any, required: true
  attr :name, :string, required: true
  attr :borne, :any, required: true
  attr :page, :integer, required: true
  attr :reserved, :any, required: true

  defp page(%{shown: {:shown, widths}} = assigns) do
    assigns = assign(assigns, :widest, List.last(widths))

    ~H"""
    <img
      id="page-image"
      src={~p"/manifestations/#{@borne}/presentation/#{@widest.profile}/#{@page}"}
      srcset={srcset(@borne, @page, @shown)}
      sizes="(min-width: 48rem) 48rem, 100vw"
      alt={"Page #{@page + 1} of #{@name}"}
      style={@reserved && "aspect-ratio: #{@reserved}"}
      class={[
        "h-auto w-full max-w-3xl rounded-md object-contain",
        "border-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-raised"
      ]}
    />
    """
  end

  defp page(%{shown: {:absent, state}} = assigns) do
    assigns = assign(assigns, :said, missing(state))

    ~H"""
    <div
      id="page-absent"
      style={@reserved && "aspect-ratio: #{@reserved}"}
      class={[
        "flex w-full max-w-3xl items-center justify-center rounded-md p-10",
        "border-[length:var(--sys-border-width-component)] border-border-strong",
        "bg-surface-raised"
      ]}
    >
      <p class="text-body-md text-on-surface-muted">{@said}</p>
    </div>
    """
  end

  # §5.2's three absences, said about the page rather than about what was run over it.
  # A clause each and no catch-all, so a state added to the vocabulary is worded here
  # rather than reaching a person as nothing at all.
  defp missing("not_held"), do: "No file is held for this, so there is no page to show."
  defp missing("not_yet_examined"), do: "This page is being made."
  defp missing("attempted_failed"), do: "This page could not be read from the file."

  # Every width of this page that is held, so a browser on a narrow screen takes a
  # narrow one. Only the widths that are there: a browser offered one that is not yet
  # made would draw nothing where it chose it.
  defp srcset(borne, page, {:shown, widths}) do
    Enum.map_join(widths, ", ", fn width ->
      "#{~p"/manifestations/#{borne}/presentation/#{width.profile}/#{page}"} #{width.width}w"
    end)
  end

  attr :page, :integer, required: true
  attr :pages, :integer, required: true

  defp position(assigns) do
    assigns = assign(assigns, :steps, Surfaces.seek_granularity("page"))

    ~H"""
    <div
      id="page-position"
      class={[
        "flex shrink-0 flex-col gap-2 px-4 py-3 sm:px-6",
        "border-t-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-raised"
      ]}
    >
      <div class="flex items-center gap-4">
        <button
          type="button"
          phx-click="page"
          phx-value-to={@page - @steps["small"]}
          disabled={@page == 0}
          class={step()}
        >
          <.icon name="hero-chevron-left-mini" />
          <span>Previous page</span>
        </button>

        <label for="page-at" class="sr-only">Position in the issue</label>
        <input
          type="range"
          id="page-at"
          name="to"
          min="0"
          max={@pages - 1}
          step={@steps["small"]}
          value={@page}
          phx-change="page-to"
          phx-debounce="120"
          aria-valuetext={"Page #{@page + 1} of #{@pages}"}
          class="grow accent-fill-solid"
        />

        <button
          type="button"
          phx-click="page"
          phx-value-to={@page + @steps["small"]}
          disabled={@page == @pages - 1}
          class={step()}
        >
          <span>Next page</span>
          <.icon name="hero-chevron-right-mini" />
        </button>
      </div>

      <span class="text-caption text-on-surface-muted">Page {@page + 1} of {@pages}</span>
    </div>
    """
  end

  defp step do
    [
      "min-h-target-touch flex shrink-0 items-center gap-2 rounded-md px-4",
      "border-[length:var(--sys-border-width-component)] border-border-strong",
      "text-body-sm text-on-surface-strong hover:bg-fill-subtle-strong",
      "disabled:text-on-surface-muted disabled:hover:bg-transparent"
    ]
  end
end
