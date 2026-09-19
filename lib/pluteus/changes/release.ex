defmodule Pluteus.Changes.Release do
  @moduledoc """
  Decides how far the change feed may be read (spec-07 §5.1).

  A write's number is taken from a sequence when its row is written, and
  transactions commit in their own order. Reading every committed number would
  let a client pass a lower number still in flight, and never see it.

  The release is two readings in order. First the highest number allocated,
  `n`; then a fresh transaction identifier, `x`. A transaction that took a
  number up to `n` had already written, so already held an identifier, before
  `x` was assigned, and identifiers are assigned in increasing order. Once the
  oldest transaction still running is no older than `x`, every one of them has
  committed or failed, and `n` is released.

  A transaction left open holds the release back until it ends. That delays
  the feed; it never lets it skip.
  """

  use GenServer

  alias Pluteus.Changes
  alias Pluteus.Repo

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  The highest number the feed may be read through.
  """
  @spec released(GenServer.server()) :: non_neg_integer()
  def released(server \\ __MODULE__), do: GenServer.call(server, :released)

  @impl GenServer
  def init(opts) do
    # A stop then waits for the reading under way, rather than killing the
    # process while it holds a connection.
    Process.flag(:trap_exit, true)

    interval =
      Keyword.get_lazy(opts, :interval, fn ->
        Keyword.fetch!(Application.fetch_env!(:pluteus, __MODULE__), :interval)
      end)

    send(self(), :advance)
    {:ok, %{released: 0, pending: nil, interval: interval}}
  end

  @impl GenServer
  def handle_call(:released, _from, state), do: {:reply, state.released, state}

  @impl GenServer
  def handle_info(:advance, state) do
    Process.send_after(self(), :advance, state.interval)
    {:noreply, state |> release() |> sample()}
  end

  defp release(%{pending: {number, xid}} = state) do
    if finished_before?(xid) do
      Changes.broadcast_released(number)
      %{state | released: number, pending: nil}
    else
      state
    end
  end

  defp release(state), do: state

  defp sample(%{pending: nil, released: released} = state) do
    case allocated() do
      number when number > released -> %{state | pending: {number, assign_xid()}}
      _nothing_new -> state
    end
  end

  defp sample(state), do: state

  defp allocated do
    [[number]] =
      Repo.query!(
        "SELECT CASE WHEN is_called THEN last_value ELSE 0 END FROM catalog_writes_id_seq"
      ).rows

    number
  end

  defp assign_xid do
    [[xid]] = Repo.query!("SELECT pg_current_xact_id()::text").rows
    xid
  end

  defp finished_before?(xid) do
    [[finished]] =
      Repo.query!("SELECT pg_snapshot_xmin(pg_current_snapshot()) >= $1::text::xid8", [xid]).rows

    finished
  end
end
