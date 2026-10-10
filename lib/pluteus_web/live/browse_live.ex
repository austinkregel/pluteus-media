defmodule PluteusWeb.BrowseLive do
  @moduledoc """
  A browse mode's surface.

  One LiveView for every mode. Every mode resolves to one faceted surface, and the modes
  differ in what they select rather than in what they are, so the mode arrives as the
  route's `live_action` and a mode gaining a surface is a route and a selection rather
  than another page.

  ## One surface, two phases

  With nothing narrowed the facet values *are* the content: the kinds, the doors into
  unfinished work, and the axes that answer nothing, named and inert. Narrow it and the
  values recede, the rows take over, and each choice becomes a chip in the rail. That is
  one surface in two phases rather than a dashboard and a results page, which is what lets
  a count mean the same thing on both.

  Each phase states the basis it orders on, because nothing here ranks: the doors go by
  what is behind them, and the rows by when the catalog took each holding.
  """

  use PluteusWeb, :live_view

  alias Pluteus.Browse
  alias Pluteus.Browse.Query
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Consumption
  alias Pluteus.Continuity.Registry, as: Continuity
  alias Pluteus.Events
  alias Pluteus.Playback
  alias Pluteus.Preferences
  alias Pluteus.Principals.Principal
  alias Pluteus.Repo
  alias Pluteus.Surfaces.Registry, as: Surfaces
  alias PluteusWeb.Absence
  alias PluteusWeb.Chrome

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    profile = %Profile{language: session["language"], assigner_id: session["assigner_id"]}

    {:ok,
     socket
     |> assign(:profile, profile)
     |> assign(:principal_name, principal_name(socket.assigns.principal_id, profile))
     |> assign(:contexts, session["contexts"] || %{})
     |> assign(:announcement, "")
     |> assign(:device_id, session["device_id"])
     |> assign(:device_revoked, session["device_revoked"])
     |> assign(:playing?, false)
     |> assign(:queue_open?, false)
     |> assign(:offering, nil)
     |> assign(:offer_seconds, 0)
     |> showing()}
  end

  # The transport is read from the queue rather than held, because the queue belongs to
  # the principal and not to this socket: a position reported from a phone changes what
  # this surface should show, and a copy kept here would go stale against it.
  defp showing(socket) do
    assign(
      socket,
      :showing,
      Playback.current(socket.assigns.principal_id, socket.assigns.profile)
    )
  end

  # The query is read from the parameters on every navigation rather than held, because
  # The narrowing is part of the address: a surface that kept it in the socket could not
  # be linked to, reloaded or gone back to.
  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    mode = Atom.to_string(socket.assigns.live_action)

    case Query.parse(mode, params) do
      {:ok, query} ->
        surface =
          Browse.surface(query, socket.assigns.principal_id, socket.assigns.profile)

        {:noreply, assign(socket, :surface, surface)}

      {:error, refusal} ->
        {:noreply, socket |> put_flash(:error, refused(refusal)) |> assign(:surface, nil)}
    end
  end

  # §12.3's controls. Each changes the queue, which is the principal's own and shared with
  # every other surface, so the answer is read back from it rather than assumed.
  #
  # A browser whose enrolment was revoked has no device to key a position or a queue by,
  # so there is nothing for these to act on and the chrome says so instead of carrying
  # them.
  @impl Phoenix.LiveView
  def handle_event("transport-play", _params, socket) do
    {:noreply, assign(socket, :playing?, not socket.assigns.playing?)}
  end

  def handle_event("transport-queue", _params, socket) do
    {:noreply, assign(socket, :queue_open?, not socket.assigns.queue_open?)}
  end

  def handle_event("transport-next", _params, socket) do
    {:noreply, jumped(socket, socket.assigns.showing.index + 1)}
  end

  def handle_event("transport-previous", _params, socket) do
    {:noreply, jumped(socket, socket.assigns.showing.index - 1)}
  end

  def handle_event("transport-jump", %{"index" => index}, socket) do
    {:noreply, jumped(socket, String.to_integer(index))}
  end

  # §13.1: every surface reports a position and no surface owns it. A report below §13.2's
  # floor or above its ceiling is discarded there, so what comes back says which — and
  # above the ceiling the res is recorded consumed, which is the deployment's own
  # judgement rather than the client's claim.
  # The bar is not re-rendered for it. The element is where the position is while
  # something plays, and a patch carrying the server's idea of it would move the element
  # back to wherever the last report left it — so the client draws its own progress and
  # the server records where it reached.
  def handle_event("transport-position", %{"res" => res_id, "position_ms" => position}, socket) do
    reported(socket, res_id, position)
    reached(socket, position)

    {:noreply, socket}
  end

  # §12.4: where the played res is a member of an ordered grouping and a next member
  # exists, the surface offers it. Nothing begins without a person having asked, so the
  # offer counts down and the queue is untouched until it is taken.
  def handle_event("transport-finished", %{"res" => res_id}, socket) do
    at = finished_at(socket)

    reported(socket, res_id, at)
    reached(socket, at)

    {:noreply, socket |> assign(:playing?, false) |> showing() |> offer()}
  end

  # Taking the offer is the person asking, so this is the one path on which audio begins
  # at the end of an entry. The interval running out advances the queue and leaves it
  # paused, which is what §12.4's two sentences say together.
  def handle_event("transport-offer-take", _params, socket) do
    advanced = socket |> cancel_offer() |> then(&jumped(&1, &1.assigns.showing.index + 1))

    {:noreply, assign(advanced, :playing?, true)}
  end

  def handle_event("transport-offer-cancel", _params, socket) do
    {:noreply, cancel_offer(socket)}
  end

  # The element could not start, and it says why: a gesture refused, a source the browser
  # will not decode and a load that was aborted are different facts, and a control that
  # looks pressed and makes no sound is worse than one that says what stopped it.
  def handle_event("transport-refused", %{"why" => why}, socket) do
    {:noreply,
     socket
     |> assign(:playing?, false)
     |> put_flash(:error, "This browser would not start playing: #{why}")}
  end

  def handle_event("play", _params, %{assigns: %{device_id: nil}} = socket) do
    {:noreply, put_flash(socket, :error, unenrolled())}
  end

  def handle_event("play", %{"res" => work_id}, socket) do
    :ok =
      Playback.play(
        socket.assigns.principal_id,
        socket.assigns.device_id,
        work_id,
        socket.assigns.profile
      )

    {:noreply, socket |> assign(:playing?, true) |> showing()}
  end

  defp unenrolled do
    "This browser holds no enrolment, so there is nowhere to record what it plays."
  end

  # A report from a browser with no enrolment has no device to be keyed by, and §13.2's
  # own refusals are the pass's to make, so each outcome is carried rather than matched
  # on: a position below the floor is not an error and not a position either.
  # The queue carries where it reached so another client resumes it and so a reload
  # starts where this one left off. A browser with no enrolment has no queue to move.
  defp reached(%{assigns: %{device_id: nil}}, _position), do: :no_device

  defp reached(socket, position) do
    Consumption.reached(socket.assigns.principal_id, position, socket.assigns.device_id)
  end

  defp reported(%{assigns: %{device_id: nil}}, _res_id, _position), do: :no_device

  defp reported(socket, res_id, position) do
    Events.report_position(%{
      principal_id: socket.assigns.principal_id,
      device_id: socket.assigns.device_id,
      res_id: res_id,
      position: position,
      unit: :millisecond,
      reported_at: DateTime.utc_now(),
      sequence: System.unique_integer([:monotonic, :positive]),
      playing: false
    })
  end

  # Where the element stopped is the end of the entry, which is the end of its region
  # where it has one and the end of the whole otherwise.
  defp finished_at(%{assigns: %{showing: %{playable: {:ok, playable}}}}) do
    case playable do
      %{to_ms: to, from_ms: from} when is_integer(to) -> to - from
      %{parts: parts} -> parts |> Enum.map(&(&1.duration_ms || 0)) |> Enum.sum()
    end
  end

  # The offer exists only where a next member does and where this principal has not
  # turned it off, which §12.4 requires be possible.
  defp offer(socket) do
    with "on" <- Preferences.held(socket.assigns.principal_id, "next_member_offer"),
         %{} = next <- Playback.next_after(socket.assigns.showing) do
      socket
      |> assign(:offering, next)
      |> assign(:offer_seconds, div(Continuity.next_member_offer_ms(), 1000))
      |> tick_offer()
    else
      _nothing_to_offer -> cancel_offer(socket)
    end
  end

  defp tick_offer(socket) do
    Process.send_after(self(), :offer_tick, 1_000)

    socket
  end

  defp cancel_offer(socket) do
    socket |> assign(:offering, nil) |> assign(:offer_seconds, 0)
  end

  @impl Phoenix.LiveView
  def handle_info(:offer_tick, %{assigns: %{offering: nil}} = socket), do: {:noreply, socket}

  def handle_info(:offer_tick, %{assigns: %{offer_seconds: 1}} = socket) do
    {:noreply, socket |> cancel_offer() |> then(&jumped(&1, &1.assigns.showing.index + 1))}
  end

  def handle_info(:offer_tick, socket) do
    {:noreply,
     socket
     |> assign(:offer_seconds, socket.assigns.offer_seconds - 1)
     |> tick_offer()}
  end

  # The queue is the principal's own and another of their devices may have changed it
  # between this render and this press, so each outcome is read back rather than assumed.
  # No catch-all: a refusal added to `jump/3` surfaces rather than being swallowed.
  defp jumped(socket, index) do
    case Playback.jump(socket.assigns.principal_id, socket.assigns.device_id, index) do
      :ok ->
        showing(socket)

      {:error, :no_queue} ->
        showing(socket)

      {:error, :current_outside_queue} ->
        socket
        |> put_flash(:error, "That is no longer an entry of the queue.")
        |> showing()
    end
  end

  # What is wrong is named rather than answered with an unnarrowed surface, which would
  # state a narrowing that did not happen.
  defp refused({:unknown_category, value}),
    do: "There is nothing here of a kind called #{value}."

  defp refused({:unknown_mode, mode}),
    do: "There is no way of looking at the catalogue called #{mode}."

  defp refused({:inert_axis, axis}),
    do: "This cannot be gone through by #{axis}."

  # The name a person recognises, and a principal's name is its person's,
  # resolved like any other res's. A principal with no person of its own has none, and the
  # chrome says so rather than being handed a stand-in.
  defp principal_name(principal_id, profile) do
    case Repo.get(Principal, principal_id) do
      %Principal{person_id: nil} -> nil
      %Principal{person_id: person_id} -> Resolution.resolve_many([person_id], profile)[person_id]
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Chrome.shell
      principal_name={@principal_name}
      contexts={@contexts}
      mode={Atom.to_string(@live_action)}
      announcement={@announcement}
      query={@surface && @surface.query}
      showing={@showing}
      playing?={@playing?}
      queue_open?={@queue_open?}
      offering={@offering}
      offer_seconds={@offer_seconds}
      device_revoked={@device_revoked}
    >
      <div id="browse" class="mx-auto w-full px-4 py-10 sm:px-6">
        <Layouts.flash_group flash={@flash} />

        <.doors :if={@surface && not narrowed?(@surface)} surface={@surface} />
        <.rows :if={@surface && narrowed?(@surface)} surface={@surface} />
      </div>
    </Chrome.shell>
    """
  end

  defp narrowed?(surface), do: Query.narrowed?(surface.query)

  # The unnarrowed phase: the facet values are the content, and every tile is a door.
  attr :surface, :map, required: true

  defp doors(assigns) do
    ~H"""
    <header class="mb-8">
      <h1 class="text-title-lg font-medium text-on-surface-strong">Everything</h1>
      <p class="mt-1 text-body-sm text-on-surface-muted">
        {@surface.total} {holdings(@surface.total)}, ordered by how many are behind each door
      </p>
    </header>

    <div class="flex flex-col gap-10">
      <.kinds facet={@surface.facets["category"]} />
      <.decades facet={@surface.facets["decade"]} />
      <.people
        facet={@surface.facets["person"]}
        labels={@surface.labels}
        places={@surface.facets["place"]}
      />
      <.unfinished doors={@surface.unfinished} />
      <.inert_axes facets={@surface.facets} />
    </div>
    """
  end

  # Oldest first, because a decade spine read in any other order is not a spine.
  attr :facet, :any, required: true

  defp decades(%{facet: {:available, []}} = assigns) do
    ~H"""
    <section aria-labelledby="decades-heading">
      <h2 id="decades-heading" class="text-title-md font-medium text-on-surface-strong">
        By when it was made
      </h2>
      <p class="mt-3 text-body-md text-on-surface-muted">
        Nothing here states when it was made.
      </p>
    </section>
    """
  end

  defp decades(assigns) do
    assigns = assign(assigns, :values, Enum.sort(elem(assigns.facet, 1)))

    ~H"""
    <section aria-labelledby="decades-heading">
      <h2 id="decades-heading" class="text-title-md font-medium text-on-surface-strong">
        By when it was made
      </h2>
      <p class="mb-3 text-body-sm text-on-surface-muted">Oldest first.</p>
      <ul class="flex flex-wrap gap-2">
        <li :for={{value, count} <- @values}>
          <a
            href={~p"/everything?#{[decade: value]}"}
            class={[
              "min-h-target-touch flex items-center gap-2 rounded-full px-4",
              "border-[length:var(--sys-border-width-component)] border-border-subtle",
              "bg-surface-raised hover:bg-surface-overlay"
            ]}
          >
            <span class="text-body-md text-on-surface-strong">{value}</span>
            <span class="font-mono text-caption text-on-surface-muted">{count}</span>
          </a>
        </li>
      </ul>
    </section>
    """
  end

  # The narrowed phase: the values recede, the rows take over, and the choices are chips
  # in the rail. Same surface, which is what lets a count mean the same thing on both.
  attr :surface, :map, required: true

  defp rows(assigns) do
    ~H"""
    <header class="mb-8">
      <h1 class="text-title-lg font-medium text-on-surface-strong">Everything</h1>
      <p class="mt-1 text-body-sm text-on-surface-muted">
        <span class="text-on-surface-strong">{@surface.total}</span>
        of {@surface.catalogue} {holdings(@surface.catalogue)}, oldest first by when it was catalogued
      </p>
    </header>

    <ol :if={@surface.entries != []} class="flex flex-col">
      <li :for={id <- @surface.entries}>
        <.row
          res={id}
          at={~p"/works/#{id}"}
          name={Map.fetch!(@surface.names, id)}
          category={@surface.categories[id]}
          members={@surface.members[id]}
          credited={@surface.credited[id] || []}
          cover={@surface.covers[id]}
        />
      </li>
    </ol>

    <p :if={@surface.entries == []} class="text-body-md text-on-surface-muted">
      Nothing is held that is all of these at once. Removing one of them will widen it.
    </p>

    <section class="mt-10" aria-labelledby="further-heading">
      <h2 id="further-heading" class="mb-3 text-title-md font-medium text-on-surface-strong">
        Narrow this further
      </h2>
      <.kinds facet={@surface.facets["category"]} />
      <div class="mt-6">
        <.inert_axes facets={@surface.facets} />
      </div>
    </section>
    """
  end

  defp holdings(1), do: "holding"
  defp holdings(_many), do: "holdings"

  # The kinds band: every category the catalogue holds, with what selecting it would
  # leave. Ordered by count descending, which the header states.
  attr :facet, :any, required: true

  defp kinds(%{facet: {:available, []}} = assigns) do
    ~H"""
    <section aria-labelledby="kinds-heading">
      <h2 id="kinds-heading" class="mb-3 text-title-md font-medium text-on-surface-strong">
        Kinds
      </h2>
      <p class="text-body-md text-on-surface-muted">
        Nothing is held, so there are no kinds to go by.
      </p>
    </section>
    """
  end

  defp kinds(%{facet: {:available, _values}} = assigns) do
    values = Enum.sort_by(elem(assigns.facet, 1), &(-elem(&1, 1)))
    most = values |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end)

    assigns = assigns |> assign(:values, values) |> assign(:most, most)

    ~H"""
    <section aria-labelledby="kinds-heading">
      <h2 id="kinds-heading" class="text-title-md font-medium text-on-surface-strong">By kind</h2>
      <p class="mb-3 text-body-sm text-on-surface-muted">Most held first.</p>
      <ul class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
        <li :for={{value, count} <- @values}>
          <.kind value={value} count={count} share={share(count, @most)} />
        </li>
      </ul>
    </section>
    """
  end

  # The glyph identifies the category; the colour groups it by broad class. The bar is
  # the count as a share of the largest.
  attr :value, :string, required: true
  attr :count, :integer, required: true
  attr :share, :integer, required: true

  defp kind(assigns) do
    assigns = assign(assigns, :mark, Surfaces.category_icon(assigns.value))

    ~H"""
    <a
      href={~p"/everything?#{[category: @value]}"}
      class={[
        "flex flex-col gap-3 rounded-md p-4",
        "border-[length:var(--sys-border-width-component)] border-border-strong",
        "bg-surface-raised hover:bg-surface-overlay"
      ]}
    >
      <span class="flex items-center gap-3">
        <.icon name={@mark.glyph} class={hue(@mark.class)} />
        <span class="grow text-body-md text-on-surface-strong">{@mark.name}</span>
        <span class="text-title-sm text-on-surface-strong">{@count}</span>
      </span>
      <span class="block h-1 overflow-hidden rounded-full bg-surface-overlay">
        <span class={["block h-full", bar(@mark.class)]} style={"width: #{@share}%"}></span>
      </span>
    </a>
    """
  end

  defp share(_count, 0), do: 0
  defp share(count, most), do: round(count / most * 100)

  # The glyph stands where a cover will. The second line distinguishes rows whose names
  # do not: two releases of one album differ only by what they gather.
  #
  # The row is a link and the play control is a button beside it, not inside: a control
  # within a link is reachable by neither keyboard path reliably, and §8.1's primary
  # action and reaching the page are two different things a person may want.
  attr :res, :string, required: true
  attr :at, :string, required: true
  attr :name, :string, required: true
  attr :category, :string, default: nil
  attr :members, :integer, default: nil
  attr :credited, :list, default: []
  attr :cover, :string, default: nil

  defp row(assigns) do
    assigns = assign(assigns, :mark, mark(assigns.category))

    ~H"""
    <div class={[
      "flex items-center gap-2 pr-2",
      "border-b-[length:var(--sys-border-width-hairline)] border-border-subtle",
      "hover:bg-fill-subtle"
    ]}>
      <a href={@at} class="flex min-w-0 grow items-center gap-4 px-2 py-3">
        <.cover at={@cover} mark={@mark} />
        <span class="flex min-w-0 grow flex-col gap-0.5">
          <span class="truncate text-body-md font-medium text-on-surface-strong">{@name}</span>
          <span class="truncate text-body-sm text-on-surface-muted">
            {said(@credited, @mark, @members)}
          </span>
        </span>
      </a>

      <button
        type="button"
        phx-click="play"
        phx-value-res={@res}
        aria-label={"Play #{@name}"}
        class={[
          "min-h-target-pointer min-w-target-pointer flex shrink-0 items-center justify-center",
          "rounded-md text-on-surface-strong hover:bg-fill-subtle"
        ]}
      >
        <.icon name="hero-play-mini" />
      </button>
    </div>
    """
  end

  # A holding nothing has said the kind of. Said in words in the place the kind would
  # have gone, with its own marker where the glyph goes: drawn as nothing instead, a row
  # with no kind is indistinguishable from one whose second line failed to render.
  defp mark(nil), do: :unkinded
  defp mark(category), do: Surfaces.category_icon(category)

  defp glyph(:unkinded), do: "state-not-yet-examined"
  defp glyph(mark), do: mark.glyph

  defp ink(:unkinded), do: "text-on-surface-muted"
  defp ink(mark), do: hue(mark.class)

  defp kind(:unkinded, _members), do: Absence.words("not_yet_examined")
  defp kind(mark, members), do: "#{mark.name}#{gathered(mark, members)}"

  # Who it is by, then what it is. The first is what a person scans a list of music for
  # and the second is what tells two holdings of one name apart, so both are said and the
  # one a person looks for leads.
  defp said([], mark, members), do: kind(mark, members)
  defp said(credited, mark, members), do: "#{Enum.join(credited, ", ")} · #{kind(mark, members)}"

  # The cover a holding is known by, asked for at the size a row draws. §11.1 serves it
  # from the presentation layer rather than from the stored bytes, and answers 202 while
  # it is being made — so the glyph is what the row shows until then and where there is
  # no cover at all, rather than a broken image.
  attr :at, :string, default: nil
  attr :mark, :any, required: true

  defp cover(assigns) do
    ~H"""
    <span class={[
      "flex size-11 shrink-0 items-center justify-center overflow-hidden rounded-md",
      "border-[length:var(--sys-border-width-hairline)] border-border-subtle",
      "bg-surface-raised"
    ]}>
      <img
        :if={@at}
        src={~p"/manifestations/#{@at}/presentation/image-320"}
        alt=""
        loading="lazy"
        class="size-full object-cover"
        onerror="this.remove()"
      />
      <.icon :if={!@at} name={glyph(@mark)} class={ink(@mark)} />
    </span>
    """
  end

  # Only where the category names what it gathers.
  defp gathered(%{members: nil}, _count), do: ""
  defp gathered(_mark, nil), do: ""
  defp gathered(%{members: noun}, 1), do: " · 1 #{String.trim_trailing(noun, "s")}"
  defp gathered(%{members: noun}, count), do: " · #{count} #{noun}"

  # Complete literals: a class built from a value generates no rule and renders colourless.
  defp hue("video"), do: "text-class-video"
  defp hue("audio"), do: "text-class-audio"
  defp hue("image"), do: "text-class-image"
  defp hue("text"), do: "text-class-text"
  defp hue("software"), do: "text-class-software"
  defp hue("package"), do: "text-class-package"

  defp bar("video"), do: "bg-class-video"
  defp bar("audio"), do: "bg-class-audio"
  defp bar("image"), do: "bg-class-image"
  defp bar("text"), do: "bg-class-text"
  defp bar("software"), do: "bg-class-software"
  defp bar("package"), do: "bg-class-package"

  # Who and where sit together because they are the same question asked of a holding, and
  # where cannot be answered, so the band says so beside the people it can name.
  attr :facet, :any, required: true
  attr :labels, :map, required: true
  attr :places, :any, required: true

  defp people(assigns) do
    assigns = assign(assigns, :values, offered(assigns.facet))

    ~H"""
    <section aria-labelledby="people-heading">
      <h2 id="people-heading" class="text-title-md font-medium text-on-surface-strong">
        By who and where
      </h2>
      <p class="mb-3 text-body-sm text-on-surface-muted">Most credited first.</p>

      <ul :if={@values != []} class="flex flex-wrap gap-2">
        <li :for={{value, count} <- @values}>
          <a
            href={~p"/everything?#{[person: value]}"}
            class={[
              "min-h-target-touch flex items-center gap-2 rounded-full px-4",
              "border-[length:var(--sys-border-width-component)] border-border-subtle",
              "bg-surface-raised hover:bg-surface-overlay"
            ]}
          >
            <.icon name="hero-user-mini" class="text-on-surface-muted" />
            <span class="text-body-md text-on-surface-strong">{@labels[value] || value}</span>
            <span class="font-mono text-caption text-on-surface-muted">{count}</span>
          </a>
        </li>
      </ul>

      <p :if={@values == []} class="text-body-md text-on-surface-muted">
        Nothing here credits anybody.
      </p>

      <p :if={match?({:inert, _why}, @places)} class="mt-3 text-body-sm text-on-surface-muted">
        Places: {elem(@places, 1)}.
      </p>
    </section>
    """
  end

  defp offered({:available, values}), do: Enum.sort_by(values, &(-elem(&1, 1)))
  defp offered({:inert, _why}), do: []

  # One door reports no figure. That is deliberate rather than an omission: a count of
  # what one person has looked at is the first thing on a surface another could hold
  # against them.
  attr :doors, :list, required: true

  defp unfinished(assigns) do
    ~H"""
    <section aria-labelledby="unfinished-heading">
      <h2 id="unfinished-heading" class="mb-3 text-title-md font-medium text-on-surface-strong">
        Unfinished
      </h2>
      <ul class="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <li :for={door <- @doors}>
          <.door
            at={door_at(door.bucket)}
            label={door_label(door.bucket)}
            count={door.count}
            open={door.any?}
            why={door_shut(door.bucket)}
          />
        </li>
      </ul>
    </section>
    """
  end

  defp door_label("nothing_you_have_looked_at"), do: "Nothing you have looked at"
  defp door_label("unverified"), do: "Unverified"
  defp door_label("no_date_recorded"), do: "No date recorded"
  defp door_label("no_kind_recorded"), do: "No kind recorded"
  defp door_label("needs_a_decision"), do: "Needs a decision"

  # Two of the four are about what a tool found rather than about the catalogue's shape,
  # and findings have their own surface, so those two lead there.
  defp door_at("unverified"), do: ~p"/findings"
  defp door_at("needs_a_decision"), do: ~p"/findings"
  defp door_at(_a_narrowing_with_no_surface_yet), do: nil

  # What a shut door says. Each states the absence its own figure measures, because the
  # four are shut for four different reasons and the one a person is owed is theirs.
  defp door_shut("nothing_you_have_looked_at"),
    do: "There is nothing here you have not looked at."

  defp door_shut("unverified"), do: "Nothing is overdue for verification."
  defp door_shut("no_date_recorded"), do: "Everything held states when it was made."
  defp door_shut("no_kind_recorded"), do: "Everything held states what kind it is."
  defp door_shut("needs_a_decision"), do: "No pair is waiting on a decision."

  # An axis that offers nothing is still named, and carries why. The reason is the axis's
  # own: they do not answer nothing for the same reason, and a person reading the surface
  # is owed the actual one.
  attr :facets, :map, required: true

  defp inert_axes(assigns) do
    ~H"""
    <section aria-labelledby="inert-heading">
      <h2 id="inert-heading" class="mb-3 text-title-md font-medium text-on-surface-strong">
        Other axes
      </h2>
      <ul class="flex flex-col gap-2">
        <li :for={{axis, {:inert, why}} <- Enum.sort(@facets)}>
          <div class={[
            "rounded-md px-4 py-3",
            "border-[length:var(--sys-border-width-component)] border-border-subtle",
            "bg-surface-raised"
          ]}>
            <p class="text-body-md text-on-surface-muted">{axis_noun(axis)}</p>
            <p class="mt-1 text-body-sm text-on-surface-muted">{why}</p>
          </div>
        </li>
      </ul>
    </section>
    """
  end

  defp axis_noun("person"), do: "People"
  defp axis_noun("place"), do: "Places"
  defp axis_noun("decade"), do: "Decades"
  defp axis_noun("language"), do: "Languages"

  # A door with somewhere to go is a link; one without is rendered disabled carrying why,
  # because a control that is available and does nothing is a lie told by an interface.
  attr :at, :string, default: nil
  attr :label, :string, required: true
  attr :count, :any, default: nil
  attr :open, :boolean, default: true
  attr :why, :string, required: true

  # Nothing behind it and nowhere to go are different, and a door says which. Both are
  # disabled, because a door onto nothing that can be opened is a lie about what is there.
  defp door(%{open: false} = assigns) do
    ~H"""
    <button
      type="button"
      disabled
      aria-describedby={"door-#{slug(@label)}-why"}
      class={[door_face(), "w-full text-left disabled:opacity-100"]}
    >
      <span class="grow text-body-md text-on-surface-muted">{@label}</span>
      <span :if={@count} class="font-mono text-caption text-on-surface-muted">{@count}</span>
    </button>
    <p id={"door-#{slug(@label)}-why"} class="sr-only">{@why}</p>
    """
  end

  defp door(%{at: nil} = assigns) do
    ~H"""
    <button
      type="button"
      disabled
      aria-describedby={"door-#{slug(@label)}-why"}
      class={[door_face(), "w-full text-left disabled:opacity-100"]}
    >
      <span class="grow text-body-md text-on-surface-strong">{@label}</span>
      <span :if={@count} class="font-mono text-caption text-on-surface-strong">{@count}</span>
    </button>
    <p id={"door-#{slug(@label)}-why"} class="sr-only">
      {@label} has no surface to open onto.
    </p>
    """
  end

  defp door(assigns) do
    ~H"""
    <a href={@at} class={door_face()}>
      <span class="grow text-body-md text-on-surface-strong">{@label}</span>
      <span :if={@count} class="font-mono text-caption text-on-surface-strong">{@count}</span>
    </a>
    """
  end

  defp door_face do
    [
      "min-h-target-touch flex items-center gap-3 rounded-md px-4",
      "border-[length:var(--sys-border-width-component)] border-border-subtle",
      "bg-surface-raised hover:bg-surface-overlay"
    ]
  end

  defp slug(label), do: label |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
end
