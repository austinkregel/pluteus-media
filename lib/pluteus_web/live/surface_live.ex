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
  alias PluteusWeb.Surfaces.Player

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
     |> assign_new(:rail_collapsed, fn -> asked == "play" end)
     |> showing(asked)}
  end

  @impl Phoenix.LiveView
  def handle_event("choose-track", %{"kind" => kind, "index" => index}, socket) do
    chosen =
      Map.put(socket.assigns.chosen, String.to_existing_atom(kind), String.to_integer(index))

    {:noreply, assign(socket, :chosen, chosen)}
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
    category = Pluteus.Catalog.category_of(work.id, Place.category_scheme())

    unless category && Surfaces.surface_of(category) == asked do
      raise NotFoundError, message: "this is not presented at #{asked}"
    end

    socket
    |> assign(:category, category)
    |> assign(:name, named(work.id, socket.assigns.profile))
    |> assign(
      :playable,
      Playback.for_work(work.id, socket.assigns.principal_id, socket.assigns.profile)
    )
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
      carries_medium={@asked == "play"}
      rail_collapsed={@rail_collapsed}
    >
      <div id="presented" class="flex h-full min-h-0 w-full flex-col">
        <Layouts.flash_group flash={@flash} />

        <.presented
          asked={@asked}
          work={@work}
          name={@name}
          category={@category}
          playable={@playable}
          chosen={@chosen}
        />
      </div>
    </Chrome.shell>
    """
  end

  # One clause per surface the registry addresses, and no catch-all, so a segment the
  # router carries and nothing renders fails here rather than drawing an empty page.
  attr :asked, :string, required: true
  attr :work, :map, required: true
  attr :name, :string, required: true
  attr :category, :string, required: true
  attr :playable, :any, required: true
  attr :chosen, :map, required: true

  defp presented(%{asked: "play"} = assigns) do
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

  defp presented(%{asked: "read"} = assigns) do
    ~H"""
    <.unbuilt surface="reader" name={@name} />
    """
  end

  defp presented(%{asked: "view"} = assigns) do
    ~H"""
    <.unbuilt surface="viewer" name={@name} />
    """
  end

  # A surface the registry addresses and nothing draws yet. Said in words rather than
  # left blank, because a blank page reads as a surface still loading.
  attr :surface, :string, required: true
  attr :name, :string, required: true

  defp unbuilt(assigns) do
    ~H"""
    <div class="mx-auto max-w-measure px-4 py-10 sm:px-6">
      <h1 class="text-title-lg font-medium text-on-surface-strong">{@name}</h1>
      <p class="mt-3 text-body-md text-on-surface-muted">
        This is presented on a {@surface}, and the {@surface} is not built yet. The
        holding is catalogued and its bytes are held; what is missing is the surface
        that shows them.
      </p>
    </div>
    """
  end
end
