defmodule PluteusWeb.Surfaces.Music do
  @moduledoc """
  The transport and its queue: the surface a recording, an album, an audiobook and a
  podcast episode are presented on ([spec-10] §12.1).

  A release is its tracks, so what the surface holds is the queue §12.3 plays through
  and the entry that is current. A recording held on its own is a queue of one.

  Playing track four of a release carried by one file is a range-limited play of that
  file, which is the address spec-04 §6.4 recorded on the manifestation (§12.2).
  """

  use PluteusWeb, :html

  alias Pluteus.Playback
  alias PluteusWeb.Surfaces.Medium

  attr :name, :string, required: true
  attr :category, :string, required: true
  attr :queue, :list, required: true
  attr :current, :integer, required: true

  def surface(assigns) do
    assigns = assign(assigns, :entry, Enum.at(assigns.queue, assigns.current))

    ~H"""
    <div class="flex w-full flex-1 flex-col">
      <Medium.band name={@name} category={@category} />

      <div class="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-4 p-4 sm:p-6">
        <.now entry={@entry} />
        <.queue entries={@queue} current={@current} />
      </div>
    </div>
    """
  end

  attr :entry, :any, required: true

  defp now(%{entry: nil} = assigns) do
    ~H"""
    <p class="text-body-md text-on-surface-muted">Nothing is held under this.</p>
    """
  end

  defp now(%{entry: %{playable: {:error, _refusal}}} = assigns) do
    ~H"""
    <div
      id="music-refusal"
      class={[
        "rounded-md p-6",
        "border-[length:var(--sys-border-width-component)] border-border-strong",
        "bg-surface-raised"
      ]}
    >
      <p class="text-body-md text-on-surface-strong">{@entry.name}</p>
      <p class="mt-1 text-body-sm text-on-surface-muted">
        {Playback.why(elem(@entry.playable, 1))}
      </p>
    </div>
    """
  end

  defp now(assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <p class="text-title-sm font-medium text-on-surface-strong">{@entry.name}</p>

      <audio
        id="player-medium"
        preload="metadata"
        aria-label={@entry.name}
        class="hidden"
        src={~p"/assets/#{first_part(@entry.playable).asset_id}/content"}
      >
      </audio>

      <Medium.controls medium="player-medium" extent={extent(@entry.playable)} />
    </div>
    """
  end

  attr :entries, :list, required: true
  attr :current, :integer, required: true

  defp queue(%{entries: []} = assigns), do: ~H""
  defp queue(%{entries: [_only]} = assigns), do: ~H""

  defp queue(assigns) do
    ~H"""
    <section id="music-queue" aria-labelledby="music-queue-heading">
      <h2 id="music-queue-heading" class="text-caption uppercase tracking-wide text-on-surface-muted">
        Queue
      </h2>

      <ol class="mt-2 flex flex-col">
        <li :for={{entry, index} <- Enum.with_index(@entries)}>
          <button
            type="button"
            phx-click="choose-entry"
            phx-value-index={index}
            aria-current={index == @current && "true"}
            class={[
              "flex min-h-target-touch w-full items-center gap-3 px-2 text-left",
              "border-b-[length:var(--sys-border-width-hairline)] border-border-subtle",
              "hover:bg-fill-subtle-strong",
              index == @current && "bg-fill-subtle"
            ]}
          >
            <span class="w-6 shrink-0 font-mono text-caption text-on-surface-muted">
              {index + 1}
            </span>
            <span class="grow truncate text-body-sm text-on-surface-strong">{entry.name}</span>
            <span class="shrink-0 font-mono text-caption text-on-surface-muted">
              {Medium.clock(extent(entry.playable))}
            </span>
          </button>
        </li>
      </ol>
    </section>
    """
  end

  defp first_part({:ok, %{parts: [part | _rest]}}), do: part

  defp extent({:error, _refusal}), do: nil
  defp extent({:ok, %{to_ms: to, from_ms: from}}) when is_integer(to), do: to - from

  defp extent({:ok, %{parts: parts}}) do
    durations = Enum.map(parts, & &1.duration_ms)

    if Enum.any?(durations, &is_nil/1), do: nil, else: Enum.sum(durations)
  end
end
