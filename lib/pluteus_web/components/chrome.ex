defmodule PluteusWeb.Chrome do
  @moduledoc """
  The chrome every rendered surface sits inside ([spec-10] §9.2, §14.1, §16.1).

  A component rather than a layout, for two reasons. `PluteusWeb.EntityLive` is
  `live_render`ed from a controller and sets no `:layout`, so a layout would not reach
  it; and the chrome carries live state — which mode is current, what the query is
  narrowed by, what is playing — that a static layout cannot be given.

  §9.2 puts the modes and the facets in one place because they are one mechanism: a mode
  resolves to a faceted surface, and narrowing it is choosing a facet value. So the rail
  holds the modes, the search §9.5 makes a surface of its own, the findings link §16.1
  requires on every surface, and the principal §14.1 requires every surface to state.

  The rail is a rail at 768px and above and a top bar with a tab bar below it under that,
  which is one responsive layout rather than two surfaces (§4.2). The transport is the
  floor under both.

  ## What is not built yet, and why it is disabled rather than absent

  §17.3: "A control for an affordance that does not exist MUST be rendered disabled and
  MUST carry a description saying why. A captions control that is available and does
  nothing is a lie told by an interface."

  No mode surface exists yet, so every mode control is disabled and says so. Removing
  them instead would make the chrome something other than the chrome, and a person could
  not see what the interface is going to be; leaving them live would make each one a lie.
  """
  use PluteusWeb, :html

  alias PluteusWeb.Layouts

  # Each glyph is the whole name of the drawing at the band the chrome renders it in.
  # A.9.5 admits no name assembled at a call site, because a class or a name built at run
  # time is invisible to the compiler and to the CSS build: the check that a glyph exists
  # is what `attr values:` gives, and it only reaches a literal.
  @modes [
    {"continue", "Continue", "hero-play-mini", "what you have not finished"},
    {"recent", "Recently added", "hero-plus-mini", "what arrived most recently"},
    {"people", "People", "hero-user-mini", "who made or appears in what you hold"},
    {"places", "Places", "hero-map-pin-mini", "where a holding was made"},
    {"time", "Time", "hero-clock-mini", "when a holding was made"},
    {"sets", "Sets", "hero-rectangle-stack-mini", "the groupings a holding belongs to"},
    {"everything", "Everything", "hero-squares-2x2-mini", "the whole catalogue"}
  ]

  @doc """
  §9.2's seven modes, each with the glyph and the noun it is named by.

  Declared here rather than read from a registry, because the vocabulary is §9.2's own
  table and a mode the deployment invented would be a mode no surface answers for.
  """
  @spec modes() :: [{String.t(), String.t(), String.t(), String.t()}]
  def modes, do: @modes

  @doc """
  Wraps a surface in the chrome.

  The `Focus` hook sits on the outermost element rather than on the surface, because
  §17.7's walk to the nearest surviving sibling has to be able to cross between the
  chrome and the surface: a removable chip lives in the rail, so focus lost when one is
  removed would otherwise land on the body with nothing to restore it.

  The live region sits here for the same reason — one per document, rendered
  unconditionally and empty, so every surface has one and none has two.
  """
  attr :principal_name, :string,
    default: nil,
    doc: "the resolved name of the acting principal's person, or nil where it has none"

  attr :contexts, :map, required: true, doc: "the intent each stored modifier carries"
  attr :mode, :string, default: nil, doc: "the current mode, where a surface is one"
  attr :announcement, :string, default: "", doc: "what the live region currently says"

  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <div id="shell" phx-hook="Focus" class="min-h-dvh bg-surface-base flex flex-col">
      <div
        id="shell-announcement"
        role="status"
        aria-live="polite"
        class="sr-only"
      >
        {@announcement}
      </div>

      <div class="flex flex-1 min-h-0">
        <.rail principal_name={@principal_name} contexts={@contexts} mode={@mode} />

        <div class="flex flex-1 min-w-0 flex-col">
          <.top_bar principal_name={@principal_name} />

          <main id="surface" class="flex-1 min-w-0 overflow-y-auto">
            {render_slot(@inner_block)}
          </main>
        </div>
      </div>

      <.transport />
      <.tab_bar mode={@mode} />
    </div>
    """
  end

  # The rail at 768px and above. Below it the same vocabulary is a top bar and a tab bar,
  # so nothing is reachable in one and not the other (§9.2).
  attr :principal_name, :string, default: nil
  attr :contexts, :map, required: true
  attr :mode, :string, default: nil

  defp rail(assigns) do
    ~H"""
    <nav
      id="rail"
      aria-label="Modes and the current query"
      class={[
        "hidden md:flex w-60 shrink-0 flex-col gap-6 overflow-y-auto",
        "border-r-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-raised px-4 py-6"
      ]}
    >
      <.identity principal_name={@principal_name} />

      <.search />

      <ul class="flex flex-col gap-1">
        <li :for={{slug, noun, glyph, what} <- modes()}>
          <.mode slug={slug} noun={noun} glyph={glyph} what={what} current={@mode == slug} />
        </li>
      </ul>

      <.findings_link />

      <details class="mt-auto">
        <summary class="min-h-target-pointer flex items-center text-body-sm text-on-surface-muted">
          How this looks
        </summary>
        <div class="pt-3">
          <Layouts.context_controls contexts={@contexts} />
        </div>
      </details>
    </nav>
    """
  end

  # §14.1: every surface states which principal it is acting as, continuously and
  # without being asked. The name is text rather than an initial, because a letter in a
  # disc is not a statement of who someone is.
  attr :principal_name, :string, default: nil

  def identity(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <span class="text-body-sm text-on-surface-muted">Acting as</span>
      <span id="identity-principal" class="text-body-md font-medium text-on-surface-strong">
        {@principal_name || "a principal with no person of its own"}
      </span>
      <button
        type="button"
        disabled
        aria-describedby="identity-switch-why"
        class={[
          "ml-auto min-h-target-pointer min-w-target-pointer flex items-center justify-center",
          "rounded-md text-on-surface-muted disabled:opacity-100"
        ]}
      >
        <.icon name="hero-chevron-up-down-mini" />
        <span class="sr-only">Switch principal</span>
      </button>
      <p id="identity-switch-why" class="sr-only">
        Switching goes through the identity provider, which this deployment does not yet ask.
      </p>
    </div>
    """
  end

  # §9.5 makes search its own surface, and none exists, so the field is disabled and says
  # so rather than reaching a browse results page, which criterion 52 forbids it sharing.
  defp search(assigns) do
    ~H"""
    <div>
      <label for="rail-search" class="sr-only">Search every name a thing carries</label>
      <div class="relative">
        <span class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-on-surface-muted">
          <.icon name="hero-magnifying-glass-mini" />
        </span>
        <input
          id="rail-search"
          type="search"
          disabled
          placeholder="Search"
          aria-describedby="rail-search-why"
          class={[
            "w-full min-h-target-touch rounded-md pl-10 pr-3 text-body-md",
            "border-[length:var(--sys-border-width-component)] border-border-strong",
            "bg-surface-base text-on-surface-strong placeholder:text-on-surface-muted"
          ]}
        />
      </div>
      <p id="rail-search-why" class="mt-1 text-caption text-on-surface-muted">
        Search has no surface yet.
      </p>
    </div>
    """
  end

  attr :slug, :string, required: true
  attr :noun, :string, required: true
  attr :glyph, :string, required: true
  attr :what, :string, required: true
  attr :current, :boolean, required: true

  defp mode(assigns) do
    ~H"""
    <button
      type="button"
      disabled
      aria-current={@current && "page"}
      aria-describedby={"mode-#{@slug}-why"}
      class={[
        "w-full min-h-target-touch flex items-center gap-3 rounded-md px-3 text-left",
        "text-body-md text-on-surface-muted disabled:opacity-100",
        "border-l-[length:var(--sys-border-width-component)] border-transparent",
        @current && "border-border-strong bg-surface-overlay font-medium text-on-surface-strong"
      ]}
    >
      <.icon name={@glyph} />
      <span>{@noun}</span>
    </button>
    <p id={"mode-#{@slug}-why"} class="sr-only">
      {@noun} shows {@what}. It has no surface yet.
    </p>
    """
  end

  # §16.1 puts the findings link on every surface. The count is what phase 5's counting
  # context answers, so the link carries the words alone until it can carry a number
  # rather than carrying one nobody computed.
  defp findings_link(assigns) do
    ~H"""
    <a
      href={~p"/findings"}
      class={[
        "min-h-target-touch flex items-center gap-3 rounded-md px-3",
        "text-body-md text-on-surface-strong",
        "hover:bg-surface-overlay"
      ]}
    >
      <.icon name="hero-exclamation-triangle-mini" />
      <span>Findings</span>
    </a>
    """
  end

  # Below the rail's breakpoint the principal still has to be stated (§14.1), so the top
  # bar carries it and the tab bar carries the modes.
  attr :principal_name, :string, default: nil

  defp top_bar(assigns) do
    ~H"""
    <div class={[
      "md:hidden flex items-center gap-3 px-4",
      "min-h-target-touch",
      "border-b-[length:var(--sys-border-width-hairline)] border-border-subtle",
      "bg-surface-raised"
    ]}>
      <span class="text-body-sm text-on-surface-muted">Acting as</span>
      <span class="text-body-sm font-medium text-on-surface-strong">
        {@principal_name || "a principal with no person of its own"}
      </span>
      <a
        href={~p"/findings"}
        class="ml-auto min-h-target-touch min-w-target-touch flex items-center justify-center rounded-md text-on-surface-strong"
      >
        <.icon name="hero-exclamation-triangle-mini" />
        <span class="sr-only">Findings</span>
      </a>
    </div>
    """
  end

  attr :mode, :string, default: nil

  defp tab_bar(assigns) do
    ~H"""
    <nav
      aria-label="Modes"
      class={[
        "md:hidden flex items-stretch",
        "border-t-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-raised"
      ]}
    >
      <button
        :for={{slug, noun, glyph, _what} <- Enum.take(modes(), 4)}
        type="button"
        disabled
        aria-current={@mode == slug && "page"}
        class={[
          "flex-1 min-h-target-touch flex flex-col items-center justify-center gap-1 py-2",
          "text-caption text-on-surface-muted disabled:opacity-100",
          @mode == slug && "text-on-surface-strong font-medium"
        ]}
      >
        <.icon name={glyph} />
        <span>{noun}</span>
      </button>
    </nav>
    """
  end

  # §12.3's transport. Nothing plays yet, so its empty rendering is what is drawn, which
  # A.9.2 makes a required rendering rather than a state to leave until later.
  defp transport(assigns) do
    ~H"""
    <div
      id="transport"
      aria-label="Transport"
      class={[
        "flex items-center gap-3 px-4",
        "min-h-target-touch",
        "border-t-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-raised"
      ]}
    >
      <p class="text-body-sm text-on-surface-muted">Nothing is playing.</p>
    </div>
    """
  end
end
