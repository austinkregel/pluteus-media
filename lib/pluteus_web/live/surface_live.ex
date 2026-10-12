defmodule PluteusWeb.SurfaceLive do
  @moduledoc """
  The surface a holding's category is presented on ([spec-10] §12.1).

  A player for a film, a reader for an ebook, a viewer for a photograph. §12.1 gives
  each category one of these and they are whole screens rather than a band of §8.4's
  entity page, so §10.1 addresses them beneath the res: `/works/{id}/play`.

  Addressed under the work because a category is the work's. The surface answers no
  representation — the entity URI keeps spec-07 §4.1's contract and stays the carrier
  of a deep link — so there is nothing to negotiate here and this is a `live` route,
  which is also what lets the player survive moving between holdings.

  Which component a path reaches is the registry's answer and not this module's: a
  category whose surface is not the one asked for is not found, rather than shown
  something else.
  """

  use PluteusWeb, :surface

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Addressing
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Place
  alias Pluteus.Lifecycle
  alias Pluteus.Paging
  alias Pluteus.Playback
  alias Pluteus.Preferences
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Asset
  alias Pluteus.Presentation.Registry
  alias Pluteus.Principals
  alias Pluteus.Principals.Principal
  alias Pluteus.Reading
  alias Pluteus.Repo
  alias Pluteus.Representation
  alias Pluteus.Surfaces.Registry, as: Surfaces
  alias PluteusWeb.Chrome
  alias PluteusWeb.GoneError
  alias PluteusWeb.Interface
  alias PluteusWeb.Native
  alias PluteusWeb.NotFoundError
  alias PluteusWeb.Settings
  alias PluteusWeb.Surfaces.Music
  alias PluteusWeb.Surfaces.Pages
  alias PluteusWeb.Surfaces.Player
  alias PluteusWeb.Surfaces.Reader
  alias PluteusWeb.Surfaces.Viewer
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
     |> assign(:preferences, Preferences.held_by(socket.assigns.principal_id))
     |> assign(:transport, Interface.transport(session))}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"id" => id} = params, _uri, socket) do
    asked = Atom.to_string(socket.assigns.live_action)

    {:noreply,
     socket
     |> assign(:work, held!(id))
     |> assign(:asked, asked)
     |> assign(:refusal, nil)
     |> assign_new(:chosen, fn -> %{audio: nil, subtitle: nil} end)
     |> showing(asked)
     |> reading(params["held"])}
  end

  defp unenrolled do
    "This browser holds no enrolment, so there is nowhere to record what it plays."
  end

  # The queue's current entry, which the chrome's transport is carrying.
  defp playing(principal_id, profile) do
    case Playback.current(principal_id, profile) do
      nil -> nil
      showing -> showing.res_id
    end
  end

  @impl Phoenix.LiveView
  def handle_event("choose-track", %{"kind" => kind, "index" => index}, socket) do
    chosen =
      Map.put(socket.assigns.chosen, String.to_existing_atom(kind), String.to_integer(index))

    {:noreply, assign(socket, :chosen, chosen)}
  end

  def handle_event("play-entry", _params, %{assigns: %{device_id: nil}} = socket) do
    {:noreply, put_flash(socket, :error, unenrolled())}
  end

  # Filled from the release and moved to the entry pressed, so what plays is the queue
  # the chrome's transport carries rather than a second medium on this page.
  def handle_event("play-entry", %{"index" => index}, socket) do
    %{principal_id: principal, device_id: device, profile: profile, work: work} = socket.assigns

    with :ok <- Playback.play(principal, device, work.id, profile),
         :ok <- Playback.jump(principal, device, String.to_integer(index)),
         :ok <- TransportLive.announce(principal) do
      {:noreply, assign(socket, :playing, playing(principal, profile))}
    else
      {:error, {:not_played, _category}} ->
        {:noreply, put_flash(socket, :error, "This is not something that plays.")}

      {:error, :no_queue} ->
        {:noreply, put_flash(socket, :error, "Nothing is held under this.")}

      {:error, :current_outside_queue} ->
        {:noreply, put_flash(socket, :error, "That is no longer an entry of the queue.")}
    end
  end

  def handle_event("rail-toggle", _params, socket) do
    {:noreply, assign(socket, :rail_collapsed, not socket.assigns.rail_collapsed)}
  end

  # §16.1 puts a failure on the surface it happened on. Whether the bytes play is the
  # browser's answer and nothing on this side can establish it, so what is shown is what
  # the element reported — worded here, because a media error code is the model's
  # vocabulary and §8.5 keeps that off a surface.
  def handle_event("medium-refused", %{"code" => code} = reported, socket) do
    {:noreply, assign(socket, :refusal, %{said: Player.refusal(code), detail: reported["said"]})}
  end

  def handle_event("page", %{"to" => to}, socket) do
    {:noreply, at(socket, String.to_integer(to))}
  end

  def handle_event("page-to", %{"to" => to}, socket) do
    {:noreply, at(socket, String.to_integer(to))}
  end

  # A setting is the principal's own (§14.5), so one is written as soon as it is pressed
  # and read back from the store rather than held in this socket: a second surface open
  # on the same holding is set the same way. One handler for every surface, because what
  # a control carries is the key, and a key no surface offers is a bug rather than a
  # refusal to report.
  def handle_event("prefer", %{"key" => key, "value" => value}, socket) do
    unless key in Settings.settable() do
      raise "#{key} is not a setting any surface offers"
    end

    {:ok, _written} = Preferences.set(socket.assigns.principal_id, key, value)

    {:noreply, assign(socket, :preferences, Preferences.held_by(socket.assigns.principal_id))}
  end

  # The text is made from the bytes on demand, so a reading opened before anything had
  # read it arrives while the job is still running. The surface asks again rather than
  # leaving a person to reload: a reading that fails records a finding, which is a state
  # of its own and ends the asking.
  @impl Phoenix.LiveView
  def handle_info(:read_again, socket) do
    {:noreply, reading(socket, socket.assigns.reader.copy.id)}
  end

  def handle_info(:page_again, socket) do
    {:noreply, socket |> assign(:looking, false) |> opened()}
  end

  # Clamped on the way in, so a copy of two pages is never open at the three hundredth
  # and a position pressed twice at the end stays at the end. A clause per surface that
  # turns pages and no catch-all, so a third of them fails here rather than moving
  # whichever of the two happens to be assigned.
  defp at(%{assigns: %{surface: "reader"}} = socket, division) do
    at = division |> max(0) |> min(divisions(socket.assigns.reader.reading) - 1)

    update(socket, :reader, &%{&1 | division: at})
  end

  defp at(%{assigns: %{surface: "page reader"}} = socket, page) do
    socket
    |> assign(:page, page |> max(0) |> min((socket.assigns.pages || 1) - 1))
    |> opened()
  end

  defp divisions({:read, %{divisions: divisions}}), do: length(divisions)
  defp divisions({:absent, _state}), do: 1

  # The four refusals, in the order the facts arrive. An identifier that is not one
  # names nothing; a work that is not held names nothing; one that was held and is not
  # stays refused rather than becoming someone else's; and a category presented
  # somewhere else is not presented here.
  defp held!(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:live, %{kind: :work} = work} <- Lifecycle.state(uuid) do
      work
    else
      :error ->
        raise NotFoundError, message: "#{id} is not an identifier"

      {:recycled, _res, recycling} ->
        raise GoneError,
          message: "this is in the recycle bin until #{recycling.purge_after}"

      {:purged, _res, _tombstone} ->
        raise GoneError, message: "this was purged, and the identifier will not be reused"

      _absent_or_another_kind ->
        raise NotFoundError, message: "no holding is held at #{id}"
    end
  end

  defp showing(socket, asked) do
    work = socket.assigns.work
    category = Catalog.category_of(work.id, Place.category_scheme())

    unless category && Surfaces.surface_of(category) == asked do
      raise NotFoundError, message: "this is not presented at #{asked}"
    end

    surface = Surfaces.category_presentation(category)["primary_surface"]

    socket
    |> assign(:category, category)
    |> assign(:surface, surface)
    |> assign(:name, named(work.id, socket.assigns.profile))
    |> assign(
      :playable,
      Playback.for_work(work.id, socket.assigns.principal_id, socket.assigns.profile)
    )
    |> assign(:queue, queued(work.id, socket.assigns.principal_id, socket.assigns.profile))
    |> assign(:playing, playing(socket.assigns.principal_id, socket.assigns.profile))
    |> assign(:borne, borne(work.id))
    |> assign(:trickplay, trickplay(surface, borne(work.id)))
    |> assign_new(:page, fn -> 0 end)
    |> assign(:pages, paged(surface, borne(work.id)))
    |> opened()
    |> assign(:facts, facts(surface, work, socket.assigns.profile))
    |> assign_new(:rail_collapsed, fn -> narrow?(surface) end)
  end

  # What the reader needs and no other surface pays for: which copy is being read, its
  # text, what people have marked in it, and how this principal has asked to be read to.
  #
  # The copy is named by the surface's own parameter rather than by an address of its
  # own, so a copy named and not held is not found — the same answer as a work nobody
  # holds, since both name something the household does not have.
  defp reading(%{assigns: %{surface: "reader"}} = socket, named) do
    copies = Reading.copies(socket.assigns.work.id)
    copy = copy!(copies, named)
    open = socket.assigns[:reader] || opened()

    socket
    |> assign(:reader, %{
      open
      | copy: copy,
        held_as: Enum.map(copies, &Map.put(&1, :reading?, reading?(&1, copy))),
        reading: read(copy),
        marks: marked(copy, socket.assigns.profile),
        credited: Reading.credited(socket.assigns.work.id, socket.assigns.profile),
        stated: copy && Reading.stated(copy.id)
    })
    |> awaited()
  end

  defp reading(socket, _named), do: assign(socket, :reader, nil)

  # What a reading carries across a patch: where in it a person is. Moving to another
  # copy keeps it, since a person who was ten pages in is ten pages into the book rather
  # than into one file of it.
  defp opened do
    %{
      copy: nil,
      held_as: [],
      reading: {:absent, "not_held"},
      marks: [],
      credited: [],
      stated: nil,
      division: 0
    }
  end

  defp copy!([], _named), do: nil
  defp copy!([first | _rest], nil), do: first

  defp copy!(copies, named) do
    Enum.find(copies, fn copy -> copy.id == named end) ||
      raise NotFoundError, message: "no copy of this is held at #{named}"
  end

  defp reading?(_copy, nil), do: false
  defp reading?(copy, reading), do: copy.id == reading.id

  defp read(nil), do: {:absent, "not_held"}
  defp read(copy), do: Reading.read(copy.id)

  defp marked(nil, _profile), do: []

  defp marked(copy, profile) do
    marks = Reading.marks(copy.id)
    people = Principals.people(Enum.map(marks, & &1.principal_id))
    names = people |> Map.values() |> Resolution.resolve_many(profile)

    for mark <- marks do
      person = people[mark.principal_id]

      Map.put(mark, :by, person && names[person] && names[person].nomen_string)
    end
  end

  # Nothing has read the text out of these bytes yet, so this asks for it and comes back
  # to look. The division is clamped on arrival, since a copy of two pages cannot be open
  # at the three hundredth.
  defp awaited(socket) do
    socket = at(socket, socket.assigns.reader.division)

    case socket.assigns.reader.reading do
      {:absent, "not_yet_examined"} ->
        :queued = Reading.ask(socket.assigns.reader.copy.id)
        if connected?(socket), do: Process.send_after(self(), :read_again, 2_000)
        socket

      _read_or_absent_for_good ->
        socket
    end
  end

  # Width belongs to the medium on a surface that shows one, which is every surface here
  # but the one that is a list of tracks. A clause each and no catch-all.
  defp narrow?("player"), do: true
  defp narrow?("reader"), do: true
  defp narrow?("scan beside its transcript"), do: true
  defp narrow?("page reader"), do: true
  defp narrow?("viewer in a justified grid"), do: true
  defp narrow?("transport and queue"), do: false
  defp narrow?("transport and chapter list"), do: false

  # §11.1's graded widths of the page being read, and §11.2's box.
  #
  # A page is asked for by being asked for: the widths that are not there are queued and
  # the surface looks again, so a page arrives without anybody reloading. The page after
  # this one is asked for as well, so turning to it finds it already made.
  defp opened(%{assigns: %{surface: "page reader", pages: pages, borne: borne}} = socket)
       when is_integer(pages) and is_binary(borne) do
    page = socket.assigns.page
    shown = Paging.open(borne, page)

    Paging.ask(borne, page)
    if page + 1 < pages, do: Paging.ask(borne, page + 1)

    socket
    |> assign_new(:looking, fn -> false end)
    |> assign(:shown, shown)
    |> assign(:reserved, Paging.reserve(shown, socket.assigns.category))
    |> looking(shown)
  end

  defp opened(socket) do
    socket
    |> assign(:shown, {:absent, "not_held"})
    |> assign(:reserved, nil)
    |> assign_new(:looking, fn -> false end)
  end

  # One look pending at a time, so turning several pages while the first is still being
  # made does not leave a look in flight for each of them. A page a tool tried and could
  # not make ends the looking, because nothing about it will change on another look.
  defp looking(socket, {:absent, "not_yet_examined"}) do
    if connected?(socket) and not socket.assigns.looking do
      Process.send_after(self(), :page_again, 2_000)
      assign(socket, :looking, true)
    else
      socket
    end
  end

  defp looking(socket, _made_or_absent_for_good), do: assign(socket, :looking, false)

  # How many pages there are to turn, which placement counted from the archive's own
  # entries (spec-01 §8.4). Nil where nothing counted them: §12.3's position is against
  # the whole, so a holding with no figure has nowhere to be in it.
  defp paged("page reader", borne) when is_binary(borne) do
    case Addressing.get_extent(borne, :page) do
      nil -> nil
      %{magnitude: pages} -> pages
    end
  end

  defp paged(_another_surface, _borne), do: nil

  # §11.3's trickplay: the frames a person scrubbing is shown, as one sprite with the
  # figures needed to find a frame in it. Asked for where it is not held yet, so the
  # second visit has it; the first shows none rather than a broken picture, because an
  # absent artefact is a state and not a failure (§11.6).
  defp trickplay("player", borne) when is_binary(borne) do
    profile = Registry.trickplay()

    case Presentation.get(borne, Map.fetch!(profile, "name")) do
      nil ->
        Presentation.ask(borne, Map.fetch!(profile, "name"))
        nil

      %Asset{descriptor: descriptor} = held ->
        %{
          at: "/#{Native.paths()[:manifestation]}/#{borne}/presentation/#{held.profile}",
          interval: Map.fetch!(descriptor, "frame_interval_ms"),
          columns: Map.fetch!(descriptor, "tile_columns"),
          frames: Map.fetch!(descriptor, "frames"),
          frame_width: Map.fetch!(descriptor, "frame_width"),
          frame_height: div(held.height, Map.fetch!(descriptor, "tile_rows"))
        }
    end
  end

  defp trickplay(_another_surface, _borne), do: nil

  # The manifestation the holding is carried by, which is the address an image profile
  # is asked for at (§11.1).
  defp borne(work_id) do
    with [expression | _rest] <- Catalog.expressions_of(work_id),
         [manifestation | _more] <- Catalog.manifestations_of(expression.id) do
      manifestation.id
    else
      _nothing_embodies_it -> nil
    end
  end

  # What the catalog holds about the holding, said as the representation already says it,
  # and only where a surface shows it: building one costs queries a player has no use for.
  #
  # A field nobody has looked at is left out rather than said as a blank — §5.2's absence
  # states are the entity page's to report, and this surface is the medium's. The name is
  # left out too, since the band above already carries it.
  defp facts("viewer in a justified grid", work, profile) do
    for {field, %{"state" => "held", "value" => value}} <- Representation.of(work, profile),
        field != "name",
        is_binary(value) or is_integer(value),
        do: {said_field(field), value}
  end

  defp facts(_another_surface, _work, _profile), do: []

  defp said_field(field), do: field |> String.replace("_", " ") |> String.capitalize()

  # A release is its tracks, so what a transport plays through is the queue the work
  # resolves to. A holding that is a member of nothing is a queue of one.
  defp queued(work_id, principal_id, profile) do
    {entries, _index} = Playback.queue_for(work_id, principal_id, profile)
    names = entries |> Enum.map(& &1.res_id) |> Resolution.resolve_many(profile)

    for %{res_id: id} <- entries do
      %{
        res_id: id,
        name: names[id] && names[id].nomen_string,
        playable: Playback.for_manifestation(id)
      }
    end
  end

  defp named(work_id, profile) do
    Resolution.resolve_many([work_id], profile)[work_id].nomen_string
  end

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
      announcement={@announcement}
      socket={@socket}
      transport={@transport}
      carries_medium={@surface == "player"}
      rail_collapsed={@rail_collapsed}
    >
      <div id="presented" class="flex h-full min-h-0 w-full flex-col">
        <Layouts.flash_group flash={@flash} />

        <.presented
          surface={@surface}
          work={@work}
          name={@name}
          category={@category}
          playable={@playable}
          queue={@queue}
          playing={@playing}
          chosen={@chosen}
          borne={@borne}
          facts={@facts}
          reader={@reader}
          preferences={@preferences}
          refusal={@refusal}
          trickplay={@trickplay}
          page={@page}
          pages={@pages}
          shown={@shown}
          reserved={@reserved}
        />
      </div>
    </Chrome.shell>
    """
  end

  # On the surface §12.1 names, not on the path it is addressed at: a path carries
  # several surfaces, and an album and a film share one while sharing nothing else.
  # No catch-all, so a surface the registry names and nothing renders fails here.
  attr :surface, :string, required: true
  attr :work, :map, required: true
  attr :name, :string, required: true
  attr :category, :string, required: true
  attr :playable, :any, required: true
  attr :queue, :list, required: true
  attr :playing, :any, required: true
  attr :chosen, :map, required: true
  attr :borne, :any, required: true
  attr :facts, :list, required: true
  attr :reader, :any, required: true
  attr :preferences, :map, required: true
  attr :refusal, :any, required: true
  attr :trickplay, :any, required: true
  attr :page, :integer, required: true
  attr :pages, :any, required: true
  attr :shown, :any, required: true
  attr :reserved, :any, required: true

  defp presented(%{surface: "player"} = assigns) do
    ~H"""
    <Player.surface
      work={@work}
      name={@name}
      category={@category}
      playable={@playable}
      chosen={@chosen}
      preferences={@preferences}
      refusal={@refusal}
      trickplay={@trickplay}
    />
    """
  end

  defp presented(%{surface: "transport and queue"} = assigns) do
    ~H"""
    <Music.surface name={@name} category={@category} queue={@queue} playing={@playing} />
    """
  end

  defp presented(%{surface: "transport and chapter list"} = assigns) do
    ~H"""
    <Music.surface name={@name} category={@category} queue={@queue} playing={@playing} />
    """
  end

  defp presented(%{surface: "reader"} = assigns) do
    ~H"""
    <Reader.surface
      work={@work}
      name={@name}
      category={@category}
      credited={@reader.credited}
      stated={@reader.stated}
      reading={@reader.reading}
      division={@reader.division}
      held_as={@reader.held_as}
      marks={@reader.marks}
      preferences={@preferences}
    />
    """
  end

  defp presented(%{surface: "scan beside its transcript"} = assigns),
    do: ~H|<.bare name={@name} />|

  defp presented(%{surface: "page reader"} = assigns) do
    ~H"""
    <Pages.surface
      name={@name}
      category={@category}
      borne={@borne}
      page={@page}
      pages={@pages}
      shown={@shown}
      reserved={@reserved}
    />
    """
  end

  defp presented(%{surface: "viewer in a justified grid"} = assigns) do
    ~H"""
    <Viewer.surface name={@name} category={@category} borne={@borne} facts={@facts} />
    """
  end

  attr :name, :string, required: true

  defp bare(assigns) do
    ~H"""
    <div class="mx-auto max-w-measure px-4 py-10 sm:px-6">
      <h1 class="text-title-lg font-medium text-on-surface-strong">{@name}</h1>
    </div>
    """
  end
end
