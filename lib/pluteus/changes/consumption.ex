defmodule Pluteus.Changes.Consumption do
  @moduledoc """
  Relays that a principal's own consumption data changed (spec-07 §5.2).

  Each consumption table notifies on the `consumption` channel from a trigger.
  Postgres delivers a notification when its transaction commits and drops it
  when it rolls back, so a device told to refresh finds the change already
  there, and is never told of one that did not happen.

  The notification names the principal and the table, and nothing of what
  was consumed.
  """

  use GenServer

  alias Pluteus.Changes
  alias Pluteus.Repo

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(_opts) do
    {:ok, listener} = Postgrex.Notifications.start_link(Repo.config())
    {:ok, _ref} = Postgrex.Notifications.listen(listener, "consumption")
    {:ok, listener}
  end

  @impl GenServer
  def handle_info({:notification, _listener, _ref, "consumption", payload}, listener) do
    [principal_id, table] = String.split(payload, " ")
    Changes.broadcast_consumption(principal_id, table)
    {:noreply, listener}
  end
end
