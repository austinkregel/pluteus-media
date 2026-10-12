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
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Place
  alias Pluteus.Lifecycle
  alias Pluteus.Playback
  alias Pluteus.Preferences
  alias Pluteus.Principals
  alias Pluteus.Principals.Principal
  alias Pluteus.Reading
  alias Pluteus.Repo
  alias Pluteus.Representation
  alias Pluteus.Surfaces.Registry, as: Surfaces
  alias PluteusWeb.Chrome
  alias PluteusWeb.GoneError
  alias PluteusWeb.Interface
  alias PluteusWeb.NotFoundError
  alias PluteusWeb.Surfaces.Music
  alias PluteusWeb.Surfaces.Player
  alias PluteusWeb.Surfaces.Reader
  alias PluteusWeb.Surfaces.Reading, as: Settings
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
     |> assign(:transport, Interface.transport(session))}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"id" => id} = params, _uri, socket) do
    asked = Atom.to_string(socket.assigns.live_action)

    {:noreply,
     socket
     |> assign(:work, held!(id))
     |> assign(:asked, asked)
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

  def handle_event("page", %{"to" => to}, socket) do
    {:noreply, at(socket, String.to_integer(to))}
  end

  def handle_event("page-to", %{"to" => to}, socket) do
    {:noreply, at(socket, String.to_integer(to))}
  end

  # A.3.6's settings are the principal's own (§14.5), so one is written as soon as it is
  # pressed and read back from the store rather than held in this socket: a second
  # surface open on the same reading is set the same way.
  def handle_event("read-as", %{"key" => key, "value" => value}, socket) do
    unless key in Settings.keys() do
      raise "#{key} is not a reading preference"
    end

    {:ok, _written} = Preferences.set(socket.assigns.principal_id, key, value)
    held = Preferences.held_by(socket.assigns.principal_id)

    {:noreply, update(socket, :reader, &%{&1 | preferences: held})}
  end

  # The text is made from the bytes on demand, so a reading opened before anything had
  # read it arrives while the job is still running. The surface asks again rather than
  # leaving a person to reload: a reading that fails records a finding, which is a state
  # of its own and ends the asking.
  @impl Phoenix.LiveView
  def handle_info(:read_again, socket) do
    {:noreply, reading(socket, socket.assigns.reader.copy.id)}
  end

  # Clamped on the way in, so a copy of two pages is never open at the three hundredth
  # and a position pressed twice at the end stays at the end.
  defp at(socket, division) do
    at = division |> max(0) |> min(pages(socket.assigns.reader.reading) - 1)

    update(socket, :reader, &%{&1 | division: at})
  end

  defp pages({:read, %{divisions: divisions}}), do: length(divisions)
  defp pages({:absent, _state}), do: 1

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
    open = socket.assigns[:reader] || opened(socket)

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

  # What a reading carries across a patch: where in it a person is, and how they have
  # asked to be read to. Moving to another copy keeps both, because a person who has set
  # the measure has set it for reading and not for one file.
  defp opened(socket) do
    %{
      copy: nil,
      held_as: [],
      reading: {:absent, "not_held"},
      marks: [],
      credited: [],
      stated: nil,
      division: 0,
      preferences: Preferences.held_by(socket.assigns.principal_id)
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
          principal_name={@principal_name}
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
  attr :principal_name, :any, required: true

  defp presented(%{surface: "player"} = assigns) do
    ~H"""
    <Player.surface
      work={@work}
      name={@name}
      category={@category}
      playable={@playable}
      chosen={@chosen}
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
      preferences={@reader.preferences}
      principal_name={@principal_name}
    />
    """
  end

  defp presented(%{surface: "scan beside its transcript"} = assigns),
    do: ~H|<.bare name={@name} />|

  defp presented(%{surface: "page reader"} = assigns), do: ~H|<.bare name={@name} />|

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
