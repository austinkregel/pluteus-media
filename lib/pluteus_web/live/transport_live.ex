defmodule PluteusWeb.TransportLive do
  @moduledoc """
  The player, as a LiveView of its own ([spec-10] §12.3).

  Rendered sticky, so it is not torn down and remounted when a surface around it is: a
  media element that is replaced stops, and a player that stops when a person opens a
  holding is not a player.

  It owns the queue's current entry and what the client is doing with it. A surface that
  starts something says so on the principal's own topic rather than handing this state
  down, because the queue outlives any one surface and is shared with every other device
  the principal plays on.
  """
  use PluteusWeb, :live_view

  alias Pluteus.Catalog.Profile
  alias Pluteus.Consumption
  alias Pluteus.Continuity.Registry, as: Continuity
  alias Pluteus.Events
  alias Pluteus.Playback
  alias Pluteus.Preferences
  alias PluteusWeb.Transport

  @doc """
  The topic a surface announces on when it starts something.
  """
  @spec topic(Ecto.UUID.t()) :: String.t()
  def topic(principal_id), do: "transport:#{principal_id}"

  @doc """
  Tells this principal's player that the queue has moved.
  """
  @spec announce(Ecto.UUID.t()) :: :ok
  def announce(principal_id) do
    Phoenix.PubSub.broadcast(Pluteus.PubSub, topic(principal_id), :queue_moved)
  end

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    profile = %Profile{language: session["language"], assigner_id: session["assigner_id"]}

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(Pluteus.PubSub, topic(session["principal_id"]))

    {:ok,
     socket
     |> assign(:profile, profile)
     |> assign(:principal_id, session["principal_id"])
     |> assign(:device_id, session["device_id"])
     |> assign(:device_revoked, session["device_revoked"])
     |> assign(:playing?, false)
     |> assign(:queue_open?, false)
     |> assign(:offering, nil)
     |> assign(:offer_seconds, 0)
     |> showing(), layout: false}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div id="player">
      <.revoked :if={@device_revoked} device={@device_revoked} />

      <Transport.bar
        :if={@showing}
        showing={@showing}
        playing?={@playing?}
        queue_open?={@queue_open?}
        offering={@offering}
        offer_seconds={@offer_seconds}
      />
    </div>
    """
  end

  # A principal who revoked this browser's enrolment has it stay revoked: nothing plays
  # here and no position is recorded.
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

  # §13.1. The bar is not re-rendered for a report: the element is where the position is
  # while something plays, and a patch would move it.
  def handle_event("transport-position", %{"res" => res_id, "position_ms" => position}, socket) do
    reported(socket, res_id, position)
    reached(socket, position)

    {:noreply, socket}
  end

  # §12.4's offer. The queue is untouched until the interval runs out or it is taken.
  def handle_event("transport-finished", %{"res" => res_id}, socket) do
    at = finished_at(socket)

    reported(socket, res_id, at)
    reached(socket, at)

    {:noreply, socket |> assign(:playing?, false) |> showing() |> offer()}
  end

  # Taking it is the person asking, which is the one path on which audio begins at the
  # end of an entry: the interval running out advances the queue and leaves it paused.
  def handle_event("transport-offer-take", _params, socket) do
    advanced = socket |> cancel_offer() |> then(&jumped(&1, &1.assigns.showing.index + 1))

    {:noreply, assign(advanced, :playing?, true)}
  end

  def handle_event("transport-offer-cancel", _params, socket) do
    {:noreply, cancel_offer(socket)}
  end

  # The element could not start, and says why: a gesture refused, a source it will not
  # decode and an aborted load are different facts.
  def handle_event("transport-refused", %{"why" => why}, socket) do
    {:noreply,
     socket
     |> assign(:playing?, false)
     |> put_flash(:error, "This browser would not start playing: #{why}")}
  end

  @impl Phoenix.LiveView
  def handle_info(:queue_moved, socket) do
    {:noreply, socket |> assign(:playing?, true) |> showing()}
  end

  def handle_info(:offer_tick, %{assigns: %{offering: nil}} = socket), do: {:noreply, socket}

  def handle_info(:offer_tick, %{assigns: %{offer_seconds: 1}} = socket) do
    {:noreply, socket |> cancel_offer() |> then(&jumped(&1, &1.assigns.showing.index + 1))}
  end

  def handle_info(:offer_tick, socket) do
    {:noreply, socket |> assign(:offer_seconds, socket.assigns.offer_seconds - 1) |> tick_offer()}
  end

  defp showing(socket) do
    assign(
      socket,
      :showing,
      Playback.current(socket.assigns.principal_id, socket.assigns.profile)
    )
  end

  # Another of the principal's devices may have changed the queue between a render and a
  # press. No catch-all, so a refusal added later surfaces.
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

  # §13.2's own refusals are the pass's to make, so each outcome is carried rather than
  # matched on. A browser with no enrolment has no device to key either by.
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

  # The end of the entry's region where it has one, and of the whole otherwise.
  defp finished_at(%{assigns: %{showing: %{playable: {:ok, playable}}}}) do
    case playable do
      %{to_ms: to, from_ms: from} when is_integer(to) -> to - from
      %{parts: parts} -> parts |> Enum.map(&(&1.duration_ms || 0)) |> Enum.sum()
    end
  end

  # Only where a next member exists and this principal has not turned it off.
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
end
