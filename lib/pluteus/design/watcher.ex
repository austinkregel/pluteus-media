defmodule Pluteus.Design.Watcher do
  @moduledoc """
  Regenerates the stylesheet when the design language changes on disk.

  Annex A's whole argument for a token file is that a value is cheap to try: A.10.1's
  consequence is that "one attribute on the document root reassigns the whole spacing
  scale, the whole type scale and the whole palette with no rebuild", and A.1's values
  are "starting values, maintained as spec-10 §20's registry". A language nobody can
  adjust without remembering a task is not cheap to try, so saving `priv/design` writes
  `assets/css/tokens.css` and Tailwind's own watcher takes it from there.

  **The cache is cleared first.** `Pluteus.Design.Tokens` holds each document in
  `:persistent_term` for the life of the node, so rebuilding without forgetting would
  regenerate the values already in memory — the same stylesheet, with nothing anywhere
  to say the edit had been ignored.

  Development only, by configuration. A release replaces `priv` rather than editing it
  underneath a running node, and there is no `assets/` directory there to write to.

  A token file that does not parse takes this process down with the error, which is the
  report. Its supervisor restarts it, and the next save rebuilds.
  """

  use GenServer

  require Logger

  alias Pluteus.Design.Build
  alias Pluteus.Design.Tokens

  # Editors save in bursts, and a burst is one edit. Long enough to coalesce a write
  # and its rename, short enough that a reload is not waiting on it.
  @settle 100

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(_opts) do
    {:ok, watcher} = FileSystem.start_link(dirs: [Tokens.root()])
    FileSystem.subscribe(watcher)

    {:ok, %{pending: nil}}
  end

  @impl GenServer
  def handle_info({:file_event, _watcher, {path, _events}}, state) do
    if String.ends_with?(path, ".json") do
      {:noreply, settle(state)}
    else
      {:noreply, state}
    end
  end

  # The watcher backend stopping is not something to carry on without: nothing would
  # rebuild and nothing would say why.
  @impl GenServer
  def handle_info({:file_event, _watcher, :stop}, state) do
    {:stop, :file_watcher_stopped, state}
  end

  @impl GenServer
  def handle_info(:rebuild, state) do
    Tokens.forget()
    written = Build.write!()

    Logger.info("The design language changed; wrote #{Path.relative_to_cwd(written)}")

    {:noreply, %{state | pending: nil}}
  end

  defp settle(%{pending: pending} = state) do
    if pending, do: Process.cancel_timer(pending)

    %{state | pending: Process.send_after(self(), :rebuild, @settle)}
  end
end
