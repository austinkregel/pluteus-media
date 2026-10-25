defmodule PluteusWeb.Surfaces.Reader do
  @moduledoc """
  The reader: the surface a document and an ebook are read on ([spec-10] §12.1).

  Three columns. What the publication is, what it divides into and what it is held as;
  the text itself at A.3.6's settings; and what people have marked in it. §12.3's
  position is counted in pages, which is the unit §20 holds this medium's seek
  granularity in, and the share of the whole is stated beside it because a page number
  says nothing about how much of a book is left.

  The name sits at the head of the column rather than in a band over the whole surface:
  a reading is the one surface whose width is the medium's, and a band would take a line
  of it from every column to say what one column already says.

  A copy is chosen by naming it, not by addressing it: the surface is the work's, and
  §10.1 gives the manifestation no second address to read it at. So the choice is a
  parameter of this surface, which is also what makes it patchable — moving between two
  copies of one book does not reload the page or interrupt what is playing.
  """

  use PluteusWeb, :html

  alias Pluteus.Reading
  alias Pluteus.Surfaces.Registry, as: Surfaces
  alias PluteusWeb.Surfaces.Medium
  alias PluteusWeb.Surfaces.Reading, as: Settings

  attr :work, :map, required: true
  attr :name, :string, required: true
  attr :category, :string, required: true
  attr :credited, :list, required: true
  attr :stated, :any, required: true
  attr :reading, :any, required: true
  attr :division, :integer, required: true
  attr :held_as, :list, required: true
  attr :marks, :list, required: true
  attr :preferences, :map, required: true

  def surface(assigns) do
    ~H"""
    <div class="flex min-h-0 w-full flex-1 flex-col lg:flex-row">
      <.aside
        work={@work}
        name={@name}
        category={@category}
        credited={@credited}
        stated={@stated}
        reading={@reading}
        division={@division}
        held_as={@held_as}
      />

      <div class="flex min-w-0 flex-1 flex-col">
        <Settings.preferences held={@preferences} />
        <.text reading={@reading} division={@division} preferences={@preferences} />
        <.position reading={@reading} division={@division} />
      </div>

      <.marked marks={@marks} />
    </div>
    """
  end

  attr :work, :map, required: true
  attr :name, :string, required: true
  attr :category, :string, required: true
  attr :credited, :list, required: true
  attr :stated, :any, required: true
  attr :reading, :any, required: true
  attr :division, :integer, required: true
  attr :held_as, :list, required: true

  defp aside(assigns) do
    ~H"""
    <aside class={[
      "flex shrink-0 flex-col lg:w-64 lg:min-h-0",
      "border-b-[length:var(--sys-border-width-hairline)] border-border-subtle",
      "lg:border-b-0 lg:border-r-[length:var(--sys-border-width-hairline)]",
      "bg-surface-raised"
    ]}>
      <section class={[
        "flex shrink-0 flex-col gap-2 px-4 py-4",
        "border-b-[length:var(--sys-border-width-hairline)] border-border-subtle"
      ]}>
        <Medium.kind category={@category} />
        <h1 class="text-title-sm font-medium text-on-surface-strong">{@name}</h1>
        <span :if={@credited != [] or @stated} class="text-body-sm text-on-surface-muted">
          {said(@credited, @stated)}
        </span>
      </section>

      <.divisions :if={pages(@reading) > 1} reading={@reading} division={@division} />

      <section class={[
        "flex shrink-0 flex-col gap-1 px-4 py-4 lg:mt-auto",
        "border-t-[length:var(--sys-border-width-hairline)] border-border-subtle"
      ]}>
        <h2 class="pb-1 text-title-md font-medium text-on-surface-strong">Held as</h2>

        <.link
          :for={copy <- @held_as}
          id={"held-#{copy.id}"}
          patch={~p"/works/#{@work.id}/read?#{[held: copy.id]}"}
          aria-current={copy.reading? && "true"}
          class={entry(copy.reading?)}
        >
          <span class="grow truncate">{copy.format}</span>
          <span :if={copy.reading?} class="shrink-0 text-caption">reading</span>
        </.link>
      </section>
    </aside>
    """
  end

  # Who it credits and when it was issued, in one line under the name. Each part is
  # there where the catalog holds it: a publication nobody is credited on says the year
  # alone rather than an empty space before it.
  defp said(credited, nil), do: Enum.join(credited, ", ")
  defp said([], stated), do: stated
  defp said(credited, stated), do: "#{Enum.join(credited, ", ")} · #{stated}"

  attr :reading, :any, required: true
  attr :division, :integer, required: true

  defp divisions(assigns) do
    ~H"""
    <section class="flex min-h-0 flex-col gap-1 px-4 py-4">
      <h2 class="pb-1 text-title-md font-medium text-on-surface-strong">Contents</h2>

      <div class="flex max-h-64 flex-col gap-1 overflow-y-auto lg:max-h-full">
        <button
          :for={{_text, at} <- Enum.with_index(pages_of(@reading))}
          type="button"
          id={"division-#{at}"}
          phx-click="page"
          phx-value-to={at}
          aria-current={at == @division && "true"}
          class={entry(at == @division)}
        >
          Page {at + 1}
        </button>
      </div>
    </section>
    """
  end

  attr :reading, :any, required: true
  attr :division, :integer, required: true
  attr :preferences, :map, required: true

  defp text(%{reading: {:absent, _state}} = assigns) do
    ~H"""
    <div class="flex flex-1 items-start px-4 py-8 sm:px-6">
      <p id="reader-absence" class="text-body-md text-on-surface-muted">
        {missing(@reading)}
      </p>
    </div>
    """
  end

  defp text(assigns) do
    ~H"""
    <div
      id="reader-text"
      data-reading-theme={Settings.theme(@preferences)}
      class="flex-1 overflow-y-auto bg-surface-base px-4 py-8 sm:px-6"
    >
      <article
        id="reader-page"
        class="mx-auto whitespace-pre-wrap text-on-surface-strong"
        style={Settings.prose_style(@preferences)}
      >
        {page(@reading, @division)}
      </article>
    </div>
    """
  end

  attr :reading, :any, required: true
  attr :division, :integer, required: true

  defp position(assigns) do
    assigns =
      assigns
      |> assign(:pages, pages(assigns.reading))
      |> assign(:steps, Surfaces.seek_granularity("page"))

    ~H"""
    <div
      :if={@pages > 1}
      id="reader-position"
      class={[
        "flex shrink-0 flex-col gap-2 px-4 py-3 sm:px-6",
        "border-t-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-raised"
      ]}
    >
      <div class="flex items-center gap-4">
        <button
          type="button"
          id="reader-previous"
          phx-click="page"
          phx-value-to={@division - @steps["small"]}
          disabled={@division == 0}
          class={step()}
        >
          <.icon name="hero-chevron-left-mini" />
          <span>Previous page</span>
        </button>

        <label for="reader-at" class="sr-only">Position in the publication</label>
        <input
          type="range"
          id="reader-at"
          name="to"
          min="0"
          max={@pages - 1}
          step={@steps["small"]}
          value={@division}
          phx-change="page-to"
          phx-debounce="120"
          aria-valuetext={spoken(@reading, @division)}
          class="grow accent-fill-solid"
        />

        <button
          type="button"
          id="reader-next"
          phx-click="page"
          phx-value-to={@division + @steps["small"]}
          disabled={@division == @pages - 1}
          class={step()}
        >
          <span>Next page</span>
          <.icon name="hero-chevron-right-mini" />
        </button>
      </div>

      <span class="text-caption text-on-surface-muted">{spoken(@reading, @division)}</span>
    </div>
    """
  end

  attr :marks, :list, required: true

  defp marked(assigns) do
    ~H"""
    <aside
      id="reader-marks"
      class={[
        "flex shrink-0 flex-col gap-4 px-4 py-4 lg:w-80 lg:overflow-y-auto",
        "border-t-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "lg:border-t-0 lg:border-l-[length:var(--sys-border-width-hairline)]"
      ]}
    >
      <div class="flex flex-wrap items-baseline gap-2">
        <h2 class="text-title-md font-medium text-on-surface-strong">Marked passages</h2>
        <span class="text-body-sm text-on-surface-muted">{length(@marks)}</span>
      </div>

      <p :if={@marks == []} class="text-body-sm text-on-surface-muted">
        Nobody has marked a passage of this.
      </p>

      <article
        :for={mark <- @marks}
        class={[
          "flex flex-col gap-2 rounded-md px-4 py-3",
          "border-[length:var(--sys-border-width-hairline)] border-border-subtle",
          "bg-surface-raised"
        ]}
      >
        <p class="text-body-sm text-on-surface-strong">{mark.passage}</p>
        <span class="text-caption text-on-surface-muted">{marked_by(mark)}</span>
      </article>

      <p class={[
        "mt-auto rounded-md px-4 py-3 text-caption text-on-surface-muted",
        "border-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-raised"
      ]}>
        Visible to the household.
      </p>
    </aside>
    """
  end

  # A mark names whoever made it, because spec-02 §10 makes an authored annotation the
  # household's and one nobody can attribute is a passage anyone might have to answer
  # for. A principal with no person recorded is still the one who marked it.
  defp marked_by(%{by: nil, marked_at: at}), do: "Marked #{said_date(at)}"
  defp marked_by(%{by: name, marked_at: at}), do: "#{name} · #{said_date(at)}"

  defp said_date(%DateTime{} = at), do: Calendar.strftime(at, "%-d %B %Y")

  # What stands in the text's place, said about the copy rather than about whatever went
  # looking for it. A clause per state and no catch-all, so a state added to §5.2 and not
  # worded here fails rather than leaving the page blank.
  defp missing({:absent, "not_held"}), do: "No text is held for this."
  defp missing({:absent, "not_yet_examined"}), do: "No text is held for this yet."
  defp missing({:absent, "attempted_failed"}), do: "No text could be read from this file."

  defp pages({:read, reading}), do: length(reading.divisions)
  defp pages({:absent, _state}), do: 0

  defp pages_of({:read, reading}), do: reading.divisions

  defp page({:read, reading}, division), do: Enum.at(reading.divisions, division)

  defp spoken({:read, reading}, division) do
    "Page #{division + 1} of #{length(reading.divisions)} · " <>
      "#{Reading.share(reading, division)}% in"
  end

  # One face for every row that stands for somewhere to go, so a copy and a page read as
  # the same kind of thing, and the one being read reads as chosen rather than hovered.
  defp entry(current?) do
    [
      "min-h-target-touch flex shrink-0 items-center gap-3 rounded-md px-3",
      "text-left text-body-md hover:bg-fill-subtle-strong",
      (current? && "bg-fill-subtle text-on-surface-strong") || "text-on-surface-muted"
    ]
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
