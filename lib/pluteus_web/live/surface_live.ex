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
  alias Pluteus.Principals.Principal
  alias Pluteus.Repo
  alias Pluteus.Surfaces.Registry, as: Surfaces
  alias PluteusWeb.Chrome
  alias PluteusWeb.GoneError
  alias PluteusWeb.Interface
  alias PluteusWeb.NotFoundError
  alias PluteusWeb.Surfaces.Music
  alias PluteusWeb.Surfaces.Player
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
  def handle_params(%{"id" => id}, _uri, socket) do
    asked = Atom.to_string(socket.assigns.live_action)

    {:noreply,
     socket
     |> assign(:work, held!(id))
     |> assign(:asked, asked)
     |> assign_new(:chosen, fn -> %{audio: nil, subtitle: nil} end)
     |> showing(asked)}
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
    |> assign_new(:rail_collapsed, fn -> surface == "player" end)
  end

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

  defp presented(%{surface: "reader"} = assigns), do: ~H|<.bare name={@name} />|

  defp presented(%{surface: "scan beside its transcript"} = assigns),
    do: ~H|<.bare name={@name} />|

  defp presented(%{surface: "page reader"} = assigns), do: ~H|<.bare name={@name} />|

  defp presented(%{surface: "viewer in a justified grid"} = assigns),
    do: ~H|<.bare name={@name} />|

  attr :name, :string, required: true

  defp bare(assigns) do
    ~H"""
    <div class="mx-auto max-w-measure px-4 py-10 sm:px-6">
      <h1 class="text-title-lg font-medium text-on-surface-strong">{@name}</h1>
    </div>
    """
  end
end
