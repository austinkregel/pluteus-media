defmodule PluteusWeb.PrincipalChannel do
  @moduledoc """
  A principal's own topic, `principal:{id}` (spec-07 §5.2): a notice that its
  consumption data changed, so another of its devices can refresh. Only that
  principal may join it (spec-06 §6.3).
  """

  use Phoenix.Channel

  alias Pluteus.Changes

  @impl Phoenix.Channel
  def join(
        "principal:" <> principal_id,
        _payload,
        %{assigns: %{principal_id: principal_id}} = socket
      ) do
    :ok = Changes.subscribe_consumption(principal_id)
    {:ok, socket}
  end

  def join(_topic, _payload, _socket), do: {:error, %{reason: "not_permitted"}}

  @impl Phoenix.Channel
  def handle_info({:consumption_changed, what}, socket) do
    push(socket, "changed", %{"data" => what})
    {:noreply, socket}
  end
end
