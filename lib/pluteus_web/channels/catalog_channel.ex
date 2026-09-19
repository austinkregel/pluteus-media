defmodule PluteusWeb.CatalogChannel do
  @moduledoc """
  The `catalog` topic (spec-07 §5.2): the number of the newest write released
  to the feed, whenever it advances, and no rows. A client fetches `/changes`
  from the last number it reconciled.
  """

  use Phoenix.Channel

  alias Pluteus.Changes
  alias Pluteus.Changes.Release

  @impl Phoenix.Channel
  def join("catalog", _payload, socket) do
    :ok = Changes.subscribe_released()
    {:ok, %{"released" => Release.released()}, socket}
  end

  @impl Phoenix.Channel
  def handle_info({:released, number}, socket) do
    push(socket, "released", %{"number" => number})
    {:noreply, socket}
  end
end
