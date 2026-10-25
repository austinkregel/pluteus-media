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

  use PluteusWeb, :surface

  alias Pluteus.Browse
  alias Pluteus.Browse.Query
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Ingest
  alias Pluteus.Playback
  alias Pluteus.Presentation.Geometry
  alias Pluteus.Principals.Principal
  alias Pluteus.Repo
  alias Pluteus.Surfaces.Registry, as: Surfaces
  alias PluteusWeb.Absence
  alias PluteusWeb.Chrome
  alias PluteusWeb.Interface
  alias PluteusWeb.Native
  alias PluteusWeb.Picture
  alias PluteusWeb.TransportLive

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    profile = %Profile{language: session["language"], assigner_id: session["assigner_id"]}

    {:ok,
     socket
     |> assign(:profile, profile)
     |> assign(:principal_name, principal_name(socket.assigns.principal_id, profile))
     |> assign(:contexts, session["contexts"] || %{})
     |> assign(:findings, Ingest.open_finding_count())
     |> assign(:announcement, "")
     |> assign(:device_id, session["device_id"])
     |> assign(:transport, Interface.transport(session))}
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

  # The player is a LiveView of its own, so a surface starts something and says so on
  # the principal's own topic rather than rendering the result itself.
  @impl Phoenix.LiveView
  def handle_event("play", _params, %{assigns: %{device_id: nil}} = socket) do
    {:noreply, put_flash(socket, :error, unenrolled())}
  end

  def handle_event("play", %{"res" => work_id}, socket) do
    socket.assigns.principal_id
    |> Playback.play(socket.assigns.device_id, work_id, socket.assigns.profile)
    |> case do
      :ok ->
        :ok = TransportLive.announce(socket.assigns.principal_id)

        {:noreply, socket}

      # No row offers this, so reaching it means a press arrived for a holding the
      # surface does not present a play control for.
      {:error, {:not_played, category}} ->
        {:noreply, put_flash(socket, :error, not_played(category))}
    end
  end

  defp unenrolled do
    "This browser holds no enrolment, so there is nowhere to record what it plays."
  end

  defp not_played(category) do
    "A #{Surfaces.category_icon(category).name |> String.downcase()} is not something " <>
      "that plays, so there is nowhere to start it."
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
      findings={@findings}
      mode={Atom.to_string(@live_action)}
      announcement={@announcement}
      query={@surface && @surface.query}
      socket={@socket}
      transport={@transport}
    >
      <div id="browse" class="mx-auto w-full px-4 py-10 sm:px-6">
        <Layouts.flash_group flash={@flash} />

        <.doors :if={@surface && gateway?(@surface)} surface={@surface} />
        <.spine :if={@surface && spine?(@surface)} surface={@surface} />
        <.agents :if={@surface && agents?(@surface)} surface={@surface} />
        <.rows :if={@surface && listed?(@surface)} surface={@surface} />
      </div>
    </Chrome.shell>
    """
  end

  # Three ways a mode opens, and a mode opens exactly one of them.
  #
  # The doors are the gateway's own: Everything is the whole catalogue, too much to list,
  # so it opens on the ways in. Time is a spine over when things were made, which §9.2
  # makes the mode rather than a band inside one. Everything else opens on what it
  # selected, because the selection is what a person went there for — and so does any
  # mode a person has narrowed, since then they have said what they are after.
  defp gateway?(surface), do: surface.query.mode == "everything" and not narrowed?(surface)
  defp spine?(surface), do: surface.query.mode == "time" and not narrowed?(surface)
  defp agents?(surface), do: surface.query.mode == "people" and not narrowed?(surface)

  defp listed?(surface) do
    not gateway?(surface) and not spine?(surface) and not agents?(surface)
  end

  defp narrowed?(surface), do: Query.narrowed?(surface.query)

  # The unnarrowed phase: the facet values are the content, and every tile is a door.
  attr :surface, :map, required: true

  defp doors(assigns) do
    ~H"""
    <header class="mb-8">
      <h1 class="text-title-lg font-medium text-on-surface-strong">Everything</h1>
      <p class="mt-1 text-body-sm text-on-surface-muted">
        {Enum.join(standing(@surface), " · ")}
      </p>
    </header>

    <div class="flex flex-col gap-10">
      <.kinds facet={@surface.facets["category"]} />
      <.decades facet={@surface.facets["decade"]} undated={undated(@surface.unfinished)} />
      <.people
        facet={@surface.facets["person"]}
        labels={@surface.labels}
        uncredited={@surface.uncredited}
        places={@surface.facets["place"]}
      />
      <.unfinished doors={@surface.unfinished} />
      <.inert_axes facets={@surface.facets} />
    </div>
    """
  end

  # What the catalogue stands at: how much is held, how much room it takes, and how far
  # back it goes. An empty catalogue has no size worth stating and was never acquired,
  # so those are left out rather than reported as nought and never.
  defp standing(surface) do
    ["#{surface.total} #{holdings(surface.total)}"] ++
      extent_said(surface.bytes) ++ acquired_said(surface.first_acquired)
  end

  defp extent_said(0), do: []
  defp extent_said(bytes), do: [room(bytes)]

  defp acquired_said(nil), do: []

  defp acquired_said(at),
    do: ["first acquired #{Calendar.strftime(at, "%-d %B %Y")}"]

  # Decimal rather than binary multiples, which is what a disk is sold and reported in.
  @units ~w(bytes kB MB GB TB)

  defp room(bytes), do: room(bytes / 1, @units)

  defp room(size, [unit]), do: "#{Float.round(size, 1)} #{unit}"
  defp room(size, [unit | _larger]) when size < 1000, do: "#{Float.round(size, 1)} #{unit}"
  defp room(size, [_unit | larger]), do: room(size / 1000, larger)

  # The holdings whose date nothing recorded, which the spine cannot place and the band
  # would otherwise leave out of its own total.
  defp undated(doors) do
    Enum.find_value(doors, 0, &(&1.bucket == "no_date_recorded" && &1.count))
  end

  # §9.2's Time: the spine is the mode rather than a band inside another one, so a decade
  # leads further into Time rather than out of it.
  attr :surface, :map, required: true

  defp spine(assigns) do
    ~H"""
    <header class="mb-8">
      <h1 class="text-title-lg font-medium text-on-surface-strong">{showing(@surface)}</h1>
      <p class="mt-1 text-body-sm text-on-surface-muted">
        <span class="text-on-surface-strong">{@surface.total}</span>
        of {@surface.catalogue} {holdings(@surface.catalogue)}
      </p>
    </header>

    <.decades
      facet={@surface.facets["decade"]}
      undated={undated(@surface.unfinished)}
      at={~p"/time"}
    />
    """
  end

  # §9.2's People: the agents a household's holdings credit, each leading to its own
  # page rather than to the holdings narrowed by it — a person is a res, and the page
  # that is about them is theirs.
  attr :surface, :map, required: true

  defp agents(assigns) do
    assigns = assign(assigns, :values, offered(assigns.surface.facets["person"]))

    ~H"""
    <header class="mb-8">
      <h1 class="text-title-lg font-medium text-on-surface-strong">{showing(@surface)}</h1>
      <p class="mt-1 text-body-sm text-on-surface-muted">
        <span class="text-on-surface-strong">{length(@values)}</span>
        {agents_said(length(@values))} credited across {@surface.catalogue}
        {holdings(@surface.catalogue)}
      </p>
    </header>

    <ul :if={@values != []} class="flex flex-col divide-y divide-border-subtle">
      <li :for={{id, count} <- @values}>
        <.link
          id={"people-list-#{id}"}
          navigate={at(@surface.agents[id], id)}
          class="flex min-h-target-touch items-center gap-3 py-3 hover:bg-fill-subtle-strong"
        >
          <.icon name="hero-user-mini" class="shrink-0 text-on-surface-muted" />
          <span class="grow truncate text-body-md text-on-surface-strong">
            {@surface.labels[id] || id}
          </span>
          <span class="shrink-0 font-mono text-caption text-on-surface-muted">{count}</span>
        </.link>
      </li>
    </ul>

    <p :if={@values == []} class="text-body-md text-on-surface-muted">
      Nothing held credits anybody.
    </p>

    <p :if={@surface.uncredited > 0} class="mt-6 text-body-sm text-on-surface-muted">
      {@surface.uncredited} {holdings(@surface.uncredited)} credit nobody yet.
    </p>
    """
  end

  defp agents_said(1), do: "person"
  defp agents_said(_many), do: "people"

  # spec-01 §3.1's three agent kinds are three addresses, and which one an agent has is
  # the catalogue's answer rather than this surface's to assume.
  defp at(kind, id), do: "/#{Map.fetch!(Native.paths(), kind)}/#{id}"

  # Oldest first, because a decade spine read in any other order is not a spine.
  attr :facet, :any, required: true
  attr :undated, :integer, default: 0
  attr :at, :string, default: "/everything"

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
    values = Enum.sort(elem(assigns.facet, 1))
    most = values |> Enum.map(&elem(&1, 1)) |> Enum.max()

    assigns = assigns |> assign(:values, values) |> assign(:most, most)

    ~H"""
    <section aria-labelledby="decades-heading">
      <h2 id="decades-heading" class="text-title-md font-medium text-on-surface-strong">
        By when it was made
      </h2>
      <ul class="mt-3 flex items-end gap-2">
        <li :for={{value, count} <- @values} class="flex min-w-0 grow basis-0 flex-col">
          <.link
            id={"decade-#{value}"}
            patch={"#{@at}?#{URI.encode_query(decade: value)}"}
            class="group flex flex-col gap-2"
          >
            <span class="flex h-24 items-end" aria-hidden="true">
              <span
                class={[
                  "block w-full rounded-sm bg-fill-subtle",
                  "group-hover:bg-fill-subtle-strong"
                ]}
                style={"height: #{height(count, @most)}%"}
              >
              </span>
            </span>
            <span class="truncate text-body-sm text-on-surface-strong">{value}</span>
            <span class="font-mono text-caption text-on-surface-muted">{count}</span>
          </.link>
        </li>

        <li
          :if={@undated > 0}
          class={[
            "flex w-20 shrink-0 flex-col gap-2 pl-3",
            "border-l-[length:var(--sys-border-width-hairline)] border-border-subtle"
          ]}
        >
          <span class="flex h-24 items-end" aria-hidden="true">
            <span
              class="block w-full rounded-sm bg-fill-subtle"
              style={"height: #{height(@undated, @most)}%"}
            >
            </span>
          </span>
          <span class="truncate text-body-sm text-on-surface-muted">Undated</span>
          <span class="font-mono text-caption text-on-surface-muted">{@undated}</span>
        </li>
      </ul>
    </section>
    """
  end

  # A bar stands for its count against the fullest decade, with a floor so that a decade
  # holding one thing is still drawn: the figure is printed under every bar, so the floor
  # cannot be the only thing a person reads a count from.
  # Clamped at both ends: the undated are not a decade and can outnumber the fullest one,
  # which fills the bar rather than drawing past the top of the band.
  defp height(count, most), do: count |> share(most) |> max(4) |> min(100)

  # The narrowed phase: the values recede, the rows take over, and the choices are chips
  # in the rail. Same surface, which is what lets a count mean the same thing on both.
  attr :surface, :map, required: true

  defp rows(assigns) do
    ~H"""
    <header class="mb-8">
      <h1 class="text-title-lg font-medium text-on-surface-strong">{showing(@surface)}</h1>
      <p class="mt-1 text-body-sm text-on-surface-muted">
        <span class="text-on-surface-strong">{@surface.total}</span>
        of {@surface.catalogue} {holdings(@surface.catalogue)}
      </p>
    </header>

    <.grid :if={@surface.entries != [] and gridded?(@surface)} surface={@surface} />

    <ol :if={@surface.entries != [] and not gridded?(@surface)} class="flex flex-col">
      <li :for={id <- @surface.entries}>
        <.row
          res={id}
          at={~p"/works/#{id}"}
          name={Map.fetch!(@surface.names, id)}
          category={@surface.categories[id]}
          members={@surface.members[id]}
          credited={@surface.credited[id] || []}
          cover={@surface.covers[id]}
          format={@surface.formats[id]}
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

  # What the surface is showing, in the household's own words for it. The kinds it has
  # been narrowed to, where it has been: a page headed with the mode's name while the
  # rail says Photographs makes a person read the chips to know what they are looking at.
  # Other axes stay in the rail, because a decade is a narrowing of a kind rather than a
  # thing with a name of its own.
  defp showing(surface) do
    case Map.get(surface.query.facets, "category", []) do
      [] -> mode_noun(surface.query.mode)
      kinds -> kinds |> Enum.map(&Surfaces.category_icon(&1).name) |> Enum.sort() |> in_words()
    end
  end

  defp mode_noun(mode) do
    {_slug, noun, _glyph, _what, _at} = Enum.find(Chrome.modes(), &(elem(&1, 0) == mode))

    noun
  end

  defp in_words([one]), do: one

  defp in_words(several),
    do: Enum.join(Enum.drop(several, -1), ", ") <> " and " <> List.last(several)

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
      <ul class="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
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
    <.link
      id={"kind-#{@value}"}
      patch={~p"/everything?#{[category: @value]}"}
      class={[
        "flex flex-col gap-3 rounded-md p-4",
        "border-[length:var(--sys-border-width-component)] border-border-strong",
        "bg-fill-subtle hover:bg-fill-subtle-strong"
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
    </.link>
    """
  end

  defp pill do
    [
      "min-h-target-touch flex items-center gap-2 rounded-full px-4",
      "border-[length:var(--sys-border-width-component)] border-border-subtle",
      "bg-fill-subtle hover:bg-fill-subtle-strong"
    ]
  end

  defp share(_count, 0), do: 0
  defp share(count, most), do: round(count / most * 100)

  # §12.1 puts a photograph on a grid rather than in a list, and §12.2 keeps a cover out
  # of one: the photograph is the picture, so a tile asks the holding itself. Where every
  # entry on the surface belongs to a grid, the rows become one — a day a household
  # browses is photographs and home video together, told apart by glyph and class colour
  # rather than by being on two surfaces.
  defp gridded?(surface) do
    surface.entries != [] and
      Enum.all?(surface.entries, fn id ->
        category = surface.categories[id]

        category != nil and
          Surfaces.category_presentation(category)["primary_surface"] ==
            "viewer in a justified grid"
      end)
  end

  # §12.1's justified grid: a tile is as wide as its own shape, so a row fills the width
  # and everything in it is one height. The shapes are §11.2's reserved boxes, which is
  # what settles a row's height before any image arrives (criterion 28).
  #
  # A row is full once the shapes in it are this wide against their height — about three
  # photographs, which is what the board draws and what keeps a tile big enough to make
  # out on a laptop.
  @row 3.6

  attr :surface, :map, required: true

  defp grid(assigns) do
    assigns = assign(assigns, :full, @row)

    ~H"""
    <ul class="flex flex-col gap-3">
      <li :for={{row, filled} <- justified(@surface)} class="flex flex-wrap gap-3">
        <div
          :for={{id, shape} <- row}
          style={"flex: #{shape} 0 0%"}
          class="min-w-40"
        >
          <.tile
            res={id}
            at={~p"/works/#{id}/view"}
            name={Map.fetch!(@surface.names, id)}
            mark={mark(@surface.categories[id])}
            borne={@surface.borne[id]}
            reserved={shape}
          />
        </div>

        <%!-- What a row short of a full one would otherwise stretch into. Without it the
              last row's two tiles take the width three took above them and stand half a
              page tall, which says they matter more than the rest. --%>
        <div :if={filled < @full} aria-hidden="true" style={"flex: #{@full - filled} 0 0%"}></div>
      </li>
    </ul>
    """
  end

  defp justified(surface) do
    surface.entries
    |> Enum.map(fn id -> {id, shape(surface, id)} end)
    |> Enum.chunk_while(
      {[], 0.0},
      fn {_id, shape} = tile, {row, filled} ->
        if filled + shape >= @row,
          do: {:cont, {Enum.reverse([tile | row]), filled + shape}, {[], 0.0}},
          else: {:cont, {[tile | row], filled + shape}}
      end,
      fn
        {[], _none} -> {:cont, {[], 0.0}}
        {row, filled} -> {:cont, {Enum.reverse(row), filled}, {[], 0.0}}
      end
    )
  end

  # A holding whose shape nothing has recorded and whose category §20 gives no figure for
  # still has to take a width, and a square is the one shape that favours no orientation.
  defp shape(surface, id), do: reserved(surface, id) || 1.0

  # §11.2's reserved box, so a row does not reflow as its images arrive. The residual
  # tile of a row decides the row, so it carries a ratio too.
  defp reserved(surface, id) do
    Geometry.reserve(surface.geometry[surface.borne[id]], surface.categories[id])
  end

  attr :res, :string, required: true
  attr :at, :string, required: true
  attr :name, :string, required: true
  attr :mark, :any, required: true
  attr :borne, :string, default: nil
  attr :reserved, :any, default: nil

  defp tile(assigns) do
    ~H"""
    <.link id={"tile-#{@res}"} navigate={@at} class="group flex flex-col gap-2">
      <span
        class={[
          "flex items-center justify-center overflow-hidden rounded-md",
          "border-[length:var(--sys-border-width-hairline)] border-border-subtle",
          "bg-surface-raised group-hover:border-border-strong"
        ]}
        style={@reserved && "aspect-ratio: #{@reserved}"}
      >
        <Picture.picture src={@borne && ~p"/manifestations/#{@borne}/presentation/image-640"}>
          <.icon name={glyph(@mark)} class={ink(@mark)} />
        </Picture.picture>
      </span>

      <span class="flex items-center gap-2">
        <.icon name={glyph(@mark)} class={["shrink-0", ink(@mark)]} />
        <span class="truncate text-body-sm text-on-surface-strong">{@name}</span>
      </span>
    </.link>
    """
  end

  # The play control is a button beside the link, not inside it: a control within a link
  # is reliably reachable by neither keyboard path. It is there only where the category's
  # primary surface runs a medium against a clock — a document is read and a photograph
  # looked at, and neither has a position to start from.
  attr :res, :string, required: true
  attr :at, :string, required: true
  attr :name, :string, required: true
  attr :category, :string, default: nil
  attr :members, :integer, default: nil
  attr :credited, :list, default: []
  attr :cover, :string, default: nil
  attr :format, :string, default: nil

  defp row(assigns) do
    assigns =
      assigns
      |> assign(:mark, mark(assigns.category))
      |> assign(:plays?, assigns.category != nil and Surfaces.plays?(assigns.category))

    ~H"""
    <div class={[
      "flex items-center gap-2 pr-2",
      "border-b-[length:var(--sys-border-width-hairline)] border-border-subtle",
      "hover:bg-fill-subtle"
    ]}>
      <.link id={"row-#{@res}"} navigate={@at} class="flex min-w-0 grow items-center gap-4 px-2 py-3">
        <.cover at={@cover} mark={@mark} />
        <span class="flex min-w-0 grow flex-col gap-0.5">
          <span class="truncate text-body-md font-medium text-on-surface-strong">{@name}</span>
          <span class="truncate text-body-sm text-on-surface-muted">
            {said(@credited, @mark, @members, @format)}
          </span>
        </span>
      </.link>

      <button
        :if={@plays?}
        type="button"
        id={"play-#{@res}"}
        phx-click="play"
        phx-value-res={@res}
        aria-label={"Play #{@name}"}
        class={[
          "min-h-target-pointer min-w-target-pointer flex shrink-0 items-center justify-center",
          "rounded-md text-on-surface-strong hover:bg-fill-subtle-strong"
        ]}
      >
        <.icon name="hero-play-mini" />
      </button>
    </div>
    """
  end

  # A kind nothing recorded, said in words where the kind would have gone (§5.3), with
  # A.8.8's marker where the glyph goes.
  defp mark(nil), do: :unkinded
  defp mark(category), do: Surfaces.category_icon(category)

  defp glyph(:unkinded), do: "state-not-yet-examined"
  defp glyph(mark), do: mark.glyph

  defp ink(:unkinded), do: "text-on-surface-muted"
  defp ink(mark), do: hue(mark.class)

  defp kind(:unkinded, _members), do: Absence.words("not_yet_examined")
  defp kind(mark, members), do: "#{mark.name}#{gathered(mark, members)}"

  # Who it is by, then what it is, then what it is held as. The last is what tells two
  # editions of one book apart: both are documents by nobody, and one is an EPUB and the
  # other plain text. It is absent where the entry's assets agree on no one format.
  defp said(credited, mark, members, format) do
    [said(credited, mark, members), format]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp said([], mark, members), do: kind(mark, members)
  defp said(credited, mark, members), do: "#{Enum.join(credited, ", ")} · #{kind(mark, members)}"

  # Asked for at the size the row draws, with the glyph beneath it for as long as no cover
  # arrives.
  attr :at, :string, default: nil
  attr :mark, :any, required: true

  defp cover(assigns) do
    ~H"""
    <span class={[
      "flex size-11 shrink-0 items-center justify-center overflow-hidden rounded-md",
      "border-[length:var(--sys-border-width-hairline)] border-border-subtle",
      "bg-surface-raised"
    ]}>
      <Picture.picture src={@at && ~p"/manifestations/#{@at}/presentation/image-320"}>
        <.icon name={glyph(@mark)} class={ink(@mark)} />
      </Picture.picture>
    </span>
    """
  end

  # Only where the category names what it gathers.
  defp gathered(%{members: nil}, _count), do: ""
  defp gathered(_mark, nil), do: ""
  defp gathered(%{members: noun}, 1), do: " · 1 #{String.trim_trailing(noun, "s")}"
  defp gathered(%{members: noun}, count), do: " · #{count} #{noun}"

  defp hue(class), do: Picture.hue(class)

  # Complete literals: a class built from a value generates no rule and renders colourless.
  defp bar("video"), do: "bg-class-video"
  defp bar("audio"), do: "bg-class-audio"
  defp bar("image"), do: "bg-class-image"
  defp bar("text"), do: "bg-class-text"
  defp bar("software"), do: "bg-class-software"
  defp bar("package"), do: "bg-class-package"

  # Who and where sit together because they are the same question asked of a holding, and
  # where cannot be answered, so the band says so beside the people it can name.
  # As many as the band shows before the rest become one control. The People mode is
  # where they all are, so this is a door's share and not a limit on who is reachable.
  @named 4

  attr :facet, :any, required: true
  attr :labels, :map, required: true
  attr :uncredited, :integer, required: true
  attr :places, :any, required: true

  defp people(assigns) do
    values = offered(assigns.facet)

    assigns =
      assigns
      |> assign(:values, Enum.take(values, @named))
      |> assign(:rest, max(length(values) - @named, 0))

    ~H"""
    <section aria-labelledby="people-heading">
      <h2 id="people-heading" class="text-title-md font-medium text-on-surface-strong">
        By who and where
      </h2>
      <ul :if={@values != []} class="mt-3 flex flex-wrap gap-2">
        <li :for={{value, count} <- @values}>
          <.link id={"people-band-#{value}"} patch={~p"/everything?#{[person: value]}"} class={pill()}>
            <.icon name="hero-user-mini" class="text-on-surface-muted" />
            <span class="text-body-md text-on-surface-strong">{@labels[value] || value}</span>
            <span class="font-mono text-caption text-on-surface-muted">{count}</span>
          </.link>
        </li>

        <li :if={@uncredited > 0}>
          <span class={pill()}>
            <span class="text-body-md text-on-surface-muted">Nobody named yet</span>
            <span class="font-mono text-caption text-on-surface-muted">{@uncredited}</span>
          </span>
        </li>

        <li :if={@rest > 0}>
          <button type="button" disabled class={pill()} aria-describedby="people-rest">
            <span class="text-body-md text-on-surface-muted">{@rest} more</span>
          </button>
          <span id="people-rest" class="sr-only">
            The rest are reached from People, which has no surface yet.
          </span>
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
        <li :for={{axis, {:inert, why}} <- elsewhere(@facets)}>
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

  # Every inert axis except the one a band of its own already answers for. Where a
  # holding was made is the second half of "By who and where", and that band states it
  # beside the people it can name, so repeating it here would have the surface report
  # one absence twice.
  defp elsewhere(facets), do: facets |> Map.drop(["place"]) |> Enum.sort()

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
      id={"door-#{slug(@label)}"}
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
      id={"door-#{slug(@label)}"}
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
    <.link id={"door-#{slug(@label)}"} navigate={@at} class={door_face()}>
      <span class="grow text-body-md text-on-surface-strong">{@label}</span>
      <span :if={@count} class="font-mono text-caption text-on-surface-strong">{@count}</span>
    </.link>
    """
  end

  defp door_face do
    [
      "min-h-target-touch flex items-center gap-3 rounded-md px-4",
      "border-[length:var(--sys-border-width-component)] border-border-subtle",
      "bg-fill-subtle hover:bg-fill-subtle-strong"
    ]
  end

  defp slug(label), do: label |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
end
