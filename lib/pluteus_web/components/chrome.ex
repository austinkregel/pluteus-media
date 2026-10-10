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

  ## A control with no surface is disabled, not absent

  §17.3: "A control for an affordance that does not exist MUST be rendered disabled and
  MUST carry a description saying why. A captions control that is available and does
  nothing is a lie told by an interface."

  So a mode whose surface the deployment does not serve is rendered disabled and says
  what it would show. Removing it would leave the vocabulary of modes incomplete, and a
  person could not tell the interface holds a way of looking they cannot reach; leaving
  it live would make it a lie.
  """
  use PluteusWeb, :html

  alias Pluteus.Browse.Query
  alias PluteusWeb.Transport

  # Each glyph is the whole name of the drawing at the band the chrome renders it in.
  # A.9.5 admits no name assembled at a call site, because a class or a name built at run
  # time is invisible to the compiler and to the CSS build: the check that a glyph exists
  # is what `attr values:` gives, and it only reaches a literal.
  # The last element is the mode's own address, or nil where this deployment serves no
  # surface for it. A mode with no address is rendered disabled carrying the reason
  # rather than linking somewhere that would answer nothing.
  @modes [
    {"continue", "Continue", "hero-play-mini", "what you have not finished", nil},
    {"recent", "Recently added", "hero-plus-mini", "what arrived most recently", nil},
    {"people", "People", "hero-user-mini", "who made or appears in what you hold", nil},
    {"places", "Places", "hero-map-pin-mini", "where a holding was made", nil},
    {"time", "Time", "hero-clock-mini", "when a holding was made", nil},
    {"sets", "Sets", "hero-rectangle-stack-mini", "the groupings a holding belongs to", nil},
    {"everything", "Everything", "hero-squares-2x2-mini", "the whole catalogue", "/everything"}
  ]

  # Four fit across a phone, and §9.2 forbids anything being reachable in the rail and
  # not here. Seven do not fit, so what this holds is every mode that has a surface plus
  # the ones a household reaches for most; a test asserts the first half, so a mode
  # gaining a surface cannot quietly become unreachable at phone width.
  @tabs ~w(continue people everything time)

  @doc """
  §9.2's seven modes, each with the glyph and the noun it is named by, and its address
  where it has a surface.

  Declared here rather than read from a registry, because the vocabulary is §9.2's own
  table and a mode the deployment invented would be a mode no surface answers for.
  """
  @spec modes() :: [{String.t(), String.t(), String.t(), String.t(), String.t() | nil}]
  def modes, do: @modes

  @doc """
  The modes the tab bar carries below the rail's breakpoint, in the order it carries them.
  """
  @spec tabs() :: [{String.t(), String.t(), String.t(), String.t(), String.t() | nil}]
  def tabs, do: for(slug <- @tabs, mode <- @modes, elem(mode, 0) == slug, do: mode)

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

  attr :query, :any,
    default: nil,
    doc: "the browse query this surface is showing, where it is a browse surface"

  attr :showing, :map,
    default: nil,
    doc: "what the transport is showing, or nil — with nothing current there is no transport"

  attr :playing?, :boolean, default: false, doc: "whether the client is playing it"
  attr :queue_open?, :boolean, default: false, doc: "whether the queue is disclosed"
  attr :offering, :any, default: nil, doc: "the next member being offered at the end"
  attr :offer_seconds, :integer, default: 0, doc: "how long the offer has left"

  attr :device_revoked, :string,
    default: nil,
    doc: "the device whose enrolment this principal revoked, where it is this browser"

  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <div id="shell" phx-hook="Focus" class="h-dvh overflow-hidden bg-surface-base flex flex-col">
      <div
        id="shell-announcement"
        role="status"
        aria-live="polite"
        class="sr-only"
      >
        {@announcement}
      </div>

      <div class="flex flex-1 min-h-0">
        <.rail principal_name={@principal_name} mode={@mode} query={@query} />

        <div class="flex flex-1 min-w-0 flex-col">
          <.top_bar principal_name={@principal_name} />

          <main id="surface" class="flex-1 min-w-0 overflow-y-auto">
            {render_slot(@inner_block)}
          </main>
        </div>
      </div>

      <.revoked :if={@device_revoked} device={@device_revoked} />

      <Transport.bar
        :if={@showing}
        showing={@showing}
        playing?={@playing?}
        queue_open?={@queue_open?}
        offering={@offering}
        offer_seconds={@offer_seconds}
      />

      <.tab_bar mode={@mode} />
    </div>
    """
  end

  # The rail at 768px and above. Below it the same vocabulary is a top bar and a tab bar,
  # so nothing is reachable in one and not the other.
  attr :principal_name, :string, default: nil
  attr :mode, :string, default: nil
  attr :query, :any, default: nil

  defp rail(assigns) do
    ~H"""
    <nav
      id="rail"
      aria-label="Modes and the current query"
      class={[
        "hidden md:flex w-60 shrink-0 flex-col overflow-y-auto",
        "border-r-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-raised"
      ]}
    >
      <div class="flex h-16 shrink-0 items-center px-4">
        <span class="text-title-sm font-medium text-on-surface-strong">Pluteus</span>
      </div>

      <.search />

      <div class="flex flex-col gap-0.5 px-3">
        <.mode
          :for={{slug, noun, glyph, what, at} <- modes()}
          slug={slug}
          noun={noun}
          glyph={glyph}
          what={what}
          at={at}
          current={@mode == slug}
        />
      </div>

      <.narrowed_by query={@query} />

      <div class="grow"></div>

      <div class="flex flex-col gap-3 px-4 pb-4">
        <.findings_link />
        <.identity principal_name={@principal_name} />
      </div>
    </nav>
    """
  end

  # The rail holds the current query and never the whole vocabulary, which is why the
  # chips are here and the facet groups are on the surface: what a person has chosen
  # belongs beside the modes, and what they could choose next belongs beside the results.
  #
  # Each active facet is removable on its own, so each chip carries the address of the
  # query without that one value — not without its axis, which would drop a second decade
  # a person meant to keep.
  attr :query, :any, default: nil

  defp narrowed_by(%{query: nil} = assigns), do: ~H""

  defp narrowed_by(assigns) do
    assigns = assign(assigns, :narrowings, Query.narrowings(assigns.query))

    ~H"""
    <div :if={@narrowings != []} class="flex flex-col gap-2">
      <h2 class="text-title-md font-medium text-on-surface-strong">Narrowed by</h2>
      <.link
        :for={{axis, value} <- @narrowings}
        patch={without(@query, axis, value)}
        aria-label={"Remove the facet #{label(axis, value)}"}
        class={[
          "min-h-target-touch flex items-center gap-2 rounded-full pl-4 pr-3",
          "border-[length:var(--sys-border-width-component)] border-border-strong",
          "bg-surface-overlay text-body-md text-on-surface-strong"
        ]}
      >
        <span class="grow">{label(axis, value)}</span>
        <.icon name="hero-x-mark-micro" />
      </.link>
    </div>
    """
  end

  # The address of the same query with one value gone. The mode's own address is where it
  # goes, because a narrowing is a narrowing *of a mode* and removing one does not leave
  # the mode.
  defp without(query, axis, value) do
    widened = Query.widen(query, axis, value)
    {_slug, _noun, _glyph, _what, at} = Enum.find(@modes, &(elem(&1, 0) == query.mode))

    case Query.to_params(widened) do
      params when params == %{} -> at
      params -> at <> "?" <> URI.encode_query(params)
    end
  end

  # A category reaches a person as the noun they would use, never as the model's own
  # spelling of it. Only the first character is raised, so a value carrying a proper noun
  # survives.
  defp label("category", value) do
    <<first::utf8, rest::binary>> = String.replace(value, "_", " ")

    String.upcase(<<first::utf8>>) <> rest
  end

  defp label(_axis, value), do: value

  # §14.1: every surface states which principal it is acting as, continuously and
  # without being asked. The name is text rather than an initial, because a letter in a
  # disc is not a statement of who someone is.
  attr :principal_name, :string, default: nil

  def identity(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-3 pt-4",
      "border-t-[length:var(--sys-border-width-hairline)] border-border-subtle"
    ]}>
      <span id="identity-principal" class="grow truncate text-body-md text-on-surface-strong">
        Acting as {@principal_name}
      </span>
      <button
        type="button"
        disabled
        aria-label={"Acting as #{@principal_name}. Switch principal."}
        aria-describedby="identity-switch-why"
        class={[
          "shrink-0 min-h-target-pointer min-w-target-pointer flex items-center justify-center",
          "rounded-md text-on-surface-muted disabled:opacity-100"
        ]}
      >
        <.icon name="hero-chevron-up-down-mini" />
      </button>
      <p id="identity-switch-why" class="sr-only">
        Switching goes through the identity provider, and this deployment has no route to it.
      </p>
    </div>
    """
  end

  # §9.5 makes search its own surface, and none exists, so the field is disabled and says
  # so rather than reaching a browse results page, which criterion 52 forbids it sharing.
  defp search(assigns) do
    ~H"""
    <div class="px-4 pb-4">
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
      <p id="rail-search-why" class="sr-only">
        Search has a surface of its own, and this deployment serves none.
      </p>
    </div>
    """
  end

  attr :slug, :string, required: true
  attr :noun, :string, required: true
  attr :glyph, :string, required: true
  attr :what, :string, required: true
  attr :at, :string, default: nil
  attr :current, :boolean, required: true

  defp mode(%{at: nil} = assigns) do
    ~H"""
    <button
      type="button"
      disabled
      aria-current={@current && "page"}
      aria-describedby={"mode-#{@slug}-why"}
      class={["w-full text-left", mode_face(@current), "disabled:opacity-100"]}
    >
      <.icon name={@glyph} />
      <span>{@noun}</span>
    </button>
    <p id={"mode-#{@slug}-why"} class="sr-only">
      {@noun} shows {@what}. This deployment serves no surface for it.
    </p>
    """
  end

  # Reaching another mode is an ordinary link: every surface is behind forward
  # authentication and declares a distance, and a live navigation would skip both.
  # Returning to the current mode is a patch — it stays in this LiveView, so it skips
  # nothing, and it is how a narrowing is cleared without stopping what is playing.
  defp mode(%{current: true} = assigns) do
    ~H"""
    <.link patch={@at} aria-current="page" class={mode_face(true)}>
      <.icon name={@glyph} />
      <span>{@noun}</span>
    </.link>
    """
  end

  defp mode(assigns) do
    ~H"""
    <a href={@at} class={mode_face(false)}>
      <.icon name={@glyph} />
      <span>{@noun}</span>
    </a>
    """
  end

  defp mode_face(current) do
    [
      "min-h-target-touch flex items-center gap-3 rounded-md px-3",
      "text-body-md text-on-surface-muted",
      "border-l-[length:var(--sys-border-width-component)] border-transparent",
      current && "border-border-strong bg-surface-overlay font-medium text-on-surface-strong"
    ]
  end

  # The findings link is on every surface. It carries the words alone rather than a
  # number nobody computed.
  defp findings_link(assigns) do
    ~H"""
    <a
      href={~p"/findings"}
      class={[
        "min-h-target-touch flex items-center gap-3 rounded-md px-3",
        "text-body-md text-on-surface-strong",
        "hover:bg-fill-subtle"
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
      <.tab
        :for={{slug, noun, glyph, what, at} <- tabs()}
        slug={slug}
        noun={noun}
        glyph={glyph}
        what={what}
        at={at}
        current={@mode == slug}
      />
    </nav>
    """
  end

  attr :slug, :string, required: true
  attr :noun, :string, required: true
  attr :glyph, :string, required: true
  attr :what, :string, required: true
  attr :at, :string, default: nil
  attr :current, :boolean, required: true

  defp tab(%{at: nil} = assigns) do
    ~H"""
    <button
      type="button"
      disabled
      aria-current={@current && "page"}
      aria-describedby={"tab-#{@slug}-why"}
      class={[tab_face(@current), "disabled:opacity-100"]}
    >
      <.icon name={@glyph} />
      <span>{@noun}</span>
    </button>
    <p id={"tab-#{@slug}-why"} class="sr-only">
      {@noun} shows {@what}. This deployment serves no surface for it.
    </p>
    """
  end

  defp tab(%{current: true} = assigns) do
    ~H"""
    <.link patch={@at} aria-current="page" class={tab_face(true)}>
      <.icon name={@glyph} />
      <span>{@noun}</span>
    </.link>
    """
  end

  defp tab(assigns) do
    ~H"""
    <a href={@at} class={tab_face(false)}>
      <.icon name={@glyph} />
      <span>{@noun}</span>
    </a>
    """
  end

  defp tab_face(current) do
    [
      "flex-1 min-h-target-touch flex flex-col items-center justify-center gap-1 py-2",
      "text-caption text-on-surface-muted",
      current && "text-on-surface-strong font-medium"
    ]
  end

  # A principal who revoked this browser's enrolment has it stay revoked, so nothing can
  # be played here and nothing can be recorded about where anybody is. Said rather than
  # left to look like a deployment that cannot play anything: taking a second credential
  # would undo in silence the thing they did deliberately.
  attr :device, :string, required: true

  defp revoked(assigns) do
    ~H"""
    <p
      id="device-revoked"
      class={[
        "px-4 py-2 text-body-sm text-on-surface-muted",
        "border-t-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-raised"
      ]}
    >
      This browser was enrolled as {@device} and that enrolment is revoked, so nothing
      plays here and no position is recorded. Enrol it again from your devices.
    </p>
    """
  end
end
