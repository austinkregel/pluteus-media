defmodule PluteusWeb.Surfaces.Music do
  @moduledoc """
  The transport and its queue: the surface a recording, an album, an audiobook and a
  podcast episode are presented on ([spec-10] §12.1).

  A release is its tracks, so the surface is the list of them and pressing one fills the
  queue from the release and starts there. What plays it is the chrome's own transport,
  which is why audio outlives moving to another surface and a film does not.

  Playing track four of a release carried by one file is a range-limited play of that
  file, which is the address spec-04 §6.4 recorded on the manifestation (§12.2).
  """

  use PluteusWeb, :html

  alias Pluteus.Playback
  alias PluteusWeb.Surfaces.Medium

  attr :name, :string, required: true
  attr :category, :string, required: true
  attr :queue, :list, required: true
  attr :playing, :any, required: true

  def surface(assigns) do
    ~H"""
    <div class="flex w-full flex-1 flex-col">
      <Medium.band name={@name} category={@category} />

      <div class="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-4 p-4 sm:p-6">
        <.entries entries={@queue} playing={@playing} />
      </div>
    </div>
    """
  end

  attr :entries, :list, required: true
  attr :playing, :any, required: true

  defp entries(%{entries: []} = assigns) do
    ~H"""
    <p class="text-body-md text-on-surface-muted">Nothing is held under this.</p>
    """
  end

  defp entries(assigns) do
    ~H"""
    <ol id="music-queue" class="flex flex-col">
      <li :for={{entry, index} <- Enum.with_index(@entries)}>
        <.entry entry={entry} index={index} playing={entry.res_id == @playing} />
      </li>
    </ol>
    """
  end

  attr :entry, :map, required: true
  attr :index, :integer, required: true
  attr :playing, :boolean, required: true

  defp entry(%{entry: %{playable: {:error, _refusal}}} = assigns) do
    ~H"""
    <div class={[
      "flex min-h-target-touch items-center gap-3 px-2",
      "border-b-[length:var(--sys-border-width-hairline)] border-border-subtle"
    ]}>
      <span class="w-6 shrink-0 font-mono text-caption text-on-surface-muted">{@index + 1}</span>
      <span class="flex min-w-0 grow flex-col">
        <span class="truncate text-body-sm text-on-surface-muted">{@entry.name}</span>
        <span class="truncate text-caption text-on-surface-muted">
          {Playback.why(elem(@entry.playable, 1))}
        </span>
      </span>
    </div>
    """
  end

  defp entry(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="play-entry"
      phx-value-index={@index}
      aria-current={@playing && "true"}
      class={[
        "flex min-h-target-touch w-full items-center gap-3 px-2 text-left",
        "border-b-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "hover:bg-fill-subtle-strong",
        @playing && "bg-fill-subtle"
      ]}
    >
      <span class="w-6 shrink-0 font-mono text-caption text-on-surface-muted">{@index + 1}</span>
      <span class="grow truncate text-body-sm text-on-surface-strong">{@entry.name}</span>
      <span class="shrink-0 font-mono text-caption text-on-surface-muted">
        {Medium.clock(extent(@entry.playable))}
      </span>
    </button>
    """
  end

  defp extent({:ok, %{to_ms: to, from_ms: from}}) when is_integer(to), do: to - from

  defp extent({:ok, %{parts: parts}}) do
    durations = Enum.map(parts, & &1.duration_ms)

    if Enum.any?(durations, &is_nil/1), do: nil, else: Enum.sum(durations)
  end
end
