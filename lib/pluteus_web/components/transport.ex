defmodule PluteusWeb.Transport do
  @moduledoc """
  The persistent transport ([spec-10] §12.3), rendered from the queue's current entry.

  A control's accessible name states the action it will perform, so play reads *Play*
  while paused. The position's readable value is in `aria-valuetext`, which is announced
  on every change where a name is announced once.

  Volume and mute are the client's own and reach no server.

  Playback speed is not here: §12.3 scopes it to the categories that carry spoken word,
  and §20 holds no table naming them.
  """
  use PluteusWeb, :html

  alias Pluteus.Continuity.Registry, as: Continuity
  alias Pluteus.Playback
  alias Pluteus.Surfaces.Registry, as: Surfaces
  alias PluteusWeb.Absence

  @doc """
  The bar, from what the transport is showing.
  """
  attr :showing, :map, required: true
  attr :playing?, :boolean, default: false
  attr :queue_open?, :boolean, default: false

  attr :offering, :any,
    default: nil,
    doc: "the next member being offered at the end, or nil"

  attr :offer_seconds, :integer, default: 0, doc: "how long the offer has left"

  def bar(assigns) do
    assigns =
      assigns
      |> assign(:steps, Surfaces.seek_granularity("millisecond"))
      |> assign(:extent, extent(assigns.showing))
      |> assign(:refusal, refusal(assigns.showing))

    ~H"""
    <div
      id="transport"
      phx-hook="MediaSession"
      data-step={@steps["large"]}
      class={[
        "flex flex-col gap-2 px-4 py-2",
        "border-t-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-raised"
      ]}
    >
      <.medium :if={@refusal == nil} showing={@showing} playing?={@playing?} />

      <.offer :if={@offering} next={@offering} seconds={@offer_seconds} />

      <.queue :if={@queue_open?} showing={@showing} />

      <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
        <.standing_for showing={@showing} />

        <span class="flex w-56 min-w-0 shrink-0 flex-col">
          <span class="truncate text-body-md text-on-surface-strong">{@showing.name}</span>
          <span class="truncate text-body-sm text-on-surface-muted">
            {@refusal || by(@showing)}
          </span>
        </span>

        <.controls
          showing={@showing}
          playing?={@playing?}
          refused?={@refusal != nil}
          queue_open?={@queue_open?}
        />

        <.position
          showing={@showing}
          extent={@extent}
          steps={@steps}
          disabled?={@extent == nil or @refusal != nil}
        />

        <.volume />
      </div>
    </div>
    """
  end

  # Said, not left to a glyph and a hue, which §5.3 and A.2.6 each forbid being the only
  # carrier.
  defp by(%{credited: [], category: category}), do: kind_of(category)

  defp by(%{credited: credited, category: category}),
    do: "#{Enum.join(credited, ", ")} · #{kind_of(category)}"

  defp kind_of(nil), do: Absence.words("not_yet_examined")
  defp kind_of(category), do: Surfaces.category_icon(category).name

  # The cover, the category glyph where there is none, and A.8.8's marker where the kind
  # is unrecorded.
  attr :showing, :map, required: true

  defp standing_for(assigns) do
    category = assigns.showing.category
    assigns = assign(assigns, :mark, category && Surfaces.category_icon(category))

    ~H"""
    <span class={[
      "flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-md",
      "border-[length:var(--sys-border-width-hairline)] border-border-subtle",
      "bg-surface-base"
    ]}>
      <img
        :if={@showing.cover}
        src={~p"/manifestations/#{@showing.cover}/presentation/image-320"}
        alt=""
        class="size-full object-cover"
        onerror="this.remove()"
      />
      <.icon :if={!@showing.cover && @mark} name={@mark.glyph} class={hue(@mark.class)} />
      <.icon
        :if={!@showing.cover && !@mark}
        name="state-not-yet-examined-mini"
        class="text-on-surface-muted"
      />
    </span>
    """
  end

  # A.9.3's toolbar: one tab stop, arrow keys within it. Both sliders stay outside, per
  # A.9.4 — a slider consumes the keys a toolbar navigates with.
  attr :showing, :map, required: true
  attr :playing?, :boolean, required: true
  attr :refused?, :boolean, required: true
  attr :queue_open?, :boolean, required: true

  defp controls(assigns) do
    assigns =
      assigns
      |> assign(:first?, assigns.showing.index == 0)
      |> assign(:last?, Playback.next_after(assigns.showing) == nil)

    ~H"""
    <div id="transport-controls" role="toolbar" aria-label="Transport" class="flex items-center gap-1">
      <button
        type="button"
        id="transport-previous"
        phx-click="transport-previous"
        disabled={@first?}
        aria-label="The entry before this one"
        class={control()}
      >
        <.icon name="previous-mini" />
      </button>

      <button
        type="button"
        id="transport-play"
        phx-click="transport-play"
        disabled={@refused?}
        aria-label={if @playing?, do: "Pause", else: "Play"}
        class={control()}
      >
        <.icon name={if @playing?, do: "hero-pause-mini", else: "hero-play-mini"} />
      </button>

      <button
        type="button"
        id="transport-next"
        phx-click="transport-next"
        disabled={@last?}
        aria-label="The entry after this one"
        class={control()}
      >
        <.icon name="next-mini" />
      </button>

      <button
        type="button"
        id="transport-mute"
        aria-label="Mute"
        aria-pressed="false"
        class={control()}
      >
        <.icon name="hero-speaker-wave-mini" />
      </button>

      <button
        type="button"
        id="transport-queue-toggle"
        phx-click="transport-queue"
        aria-expanded={to_string(@queue_open?)}
        aria-controls="transport-queue"
        aria-label={"The queue, #{length(@showing.queue)} entries"}
        class={control()}
      >
        <.icon name="hero-queue-list-mini" />
      </button>
    </div>
    """
  end

  # A native range with a step: §17.5 forbids requiring a drag, and A.2.7 assigns
  # semantic colour from element semantics, which a div with a role does not receive.
  defp volume(assigns) do
    ~H"""
    <div class="hidden items-center gap-2 sm:flex">
      <label for="transport-volume" class="sr-only">Volume</label>
      <input
        type="range"
        id="transport-volume"
        min="0"
        max="100"
        step="5"
        value="100"
        aria-valuetext="100 per cent"
        class="w-24 accent-fill-solid"
      />
    </div>
    """
  end

  attr :showing, :map, required: true
  attr :extent, :any, required: true
  attr :steps, :map, required: true
  attr :disabled?, :boolean, required: true

  defp position(assigns) do
    ~H"""
    <div class="flex min-w-0 grow basis-64 items-center gap-2">
      <span
        id="transport-elapsed"
        class="w-12 shrink-0 text-right font-mono text-caption text-on-surface-muted"
      >
        {clock(@showing.position_ms)}
      </span>

      <button
        type="button"
        id="transport-back"
        disabled={@disabled?}
        aria-label={"Back #{seconds(@steps["large"])} seconds"}
        class={control()}
      >
        <.icon name="back-10-mini" />
      </button>

      <label for="transport-position" class="sr-only">Position</label>
      <input
        type="range"
        id="transport-position"
        min="0"
        max={@extent || 0}
        step={@steps["small"]}
        value={@showing.position_ms}
        disabled={@disabled?}
        aria-valuetext={spoken(@showing.position_ms, @extent)}
        class="grow accent-fill-solid"
      />

      <button
        type="button"
        id="transport-forward"
        disabled={@disabled?}
        aria-label={"Forward #{seconds(@steps["large"])} seconds"}
        class={control()}
      >
        <.icon name="forward-30-mini" />
      </button>

      <span class="w-12 shrink-0 font-mono text-caption text-on-surface-muted">
        {clock(@extent)}
      </span>
    </div>
    """
  end

  # The parts travel as data because a holding in several files is one sequence: a
  # position is against the whole, which no single source can express.
  attr :showing, :map, required: true
  attr :playing?, :boolean, required: true

  defp medium(assigns) do
    ~H"""
    <audio
      id="transport-medium"
      data-parts={parts(@showing)}
      data-from={from(@showing)}
      data-to={to(@showing)}
      data-position={@showing.position_ms}
      data-playing={to_string(@playing?)}
      data-res={@showing.res_id}
      data-interval={Continuity.reporting_interval_ms()}
      class="hidden"
    >
    </audio>
    """
  end

  # §12.4's offer: a visible interval before it acts, cancellable, and no audio begins
  # unasked.
  attr :next, :map, required: true
  attr :seconds, :integer, required: true

  defp offer(assigns) do
    ~H"""
    <div
      id="transport-offer"
      class={[
        "flex items-center gap-3 rounded-md px-3 py-2",
        "border-[length:var(--sys-border-width-component)] border-border-strong",
        "bg-surface-overlay"
      ]}
    >
      <span class="grow truncate text-body-sm text-on-surface-strong">
        Next: {@next.name}, in {@seconds} {if @seconds == 1, do: "second", else: "seconds"}
      </span>

      <button
        type="button"
        id="transport-offer-take"
        phx-click="transport-offer-take"
        class={control()}
      >
        <span class="px-2 text-body-sm">Play it now</span>
      </button>

      <button
        type="button"
        id="transport-offer-cancel"
        phx-click="transport-offer-cancel"
        class={control()}
      >
        <span class="px-2 text-body-sm">Stop here</span>
      </button>
    </div>
    """
  end

  attr :showing, :map, required: true

  defp queue(assigns) do
    assigns = assign(assigns, :entries, appearances(assigns.showing.queue))

    ~H"""
    <section id="transport-queue" aria-label="The queue" class="max-h-48 overflow-y-auto">
      <ol class="flex flex-col">
        <li :for={{entry, index, appearance} <- @entries}>
          <button
            type="button"
            id={"queued-#{entry.res_id}-#{appearance}"}
            phx-click="transport-jump"
            phx-value-index={index}
            aria-current={index == @showing.index && "true"}
            class={[
              "min-h-target-touch flex w-full items-center gap-3 px-2 text-left",
              "hover:bg-fill-subtle-strong",
              index == @showing.index && "bg-fill-subtle"
            ]}
          >
            <span class="w-6 shrink-0 font-mono text-caption text-on-surface-muted">
              {index + 1}
            </span>
            <span class="truncate text-body-sm text-on-surface-strong">{entry.name}</span>
          </button>
        </li>
      </ol>
    </section>
    """
  end

  # A queue may hold one track twice, so an entry is named by its res and by which
  # appearance of it this is. Counted from the queue's own order rather than taken from
  # the index, so removing another entry leaves this one's identity where it was.
  defp appearances(queue) do
    {entries, _seen} =
      queue
      |> Enum.with_index()
      |> Enum.map_reduce(%{}, fn {entry, index}, seen ->
        appearance = Map.get(seen, entry.res_id, 0) + 1
        {{entry, index, appearance}, Map.put(seen, entry.res_id, appearance)}
      end)

    entries
  end

  # spec-01 §8.4's recorded figure, which §13.2's thresholds also measure against.
  defp extent(%{extent_ms: extent_ms}), do: extent_ms

  defp refusal(%{playable: {:error, refusal}}), do: Playback.why(refusal)
  defp refusal(%{playable: {:ok, _playable}}), do: nil

  defp parts(%{playable: {:ok, %{parts: parts}}}) do
    Jason.encode!(
      for part <- parts do
        %{src: ~p"/assets/#{part.asset_id}/content", duration_ms: part.duration_ms}
      end
    )
  end

  defp from(%{playable: {:ok, %{from_ms: from}}}), do: from
  defp to(%{playable: {:ok, %{to_ms: to}}}), do: to

  # A place in the whole, since a bare figure says nothing about how far through.
  defp spoken(position_ms, nil), do: "#{clock(position_ms)}, of a length not recorded"
  defp spoken(position_ms, extent), do: "#{clock(position_ms)} of #{clock(extent)}"

  defp clock(nil), do: "--:--"

  defp clock(milliseconds) do
    total = div(milliseconds, 1000)
    minutes = div(total, 60)
    seconds = rem(total, 60)

    "#{minutes}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end

  defp seconds(milliseconds), do: div(milliseconds, 1000)

  # The touch floor: A.4.2 sizes for the coarsest pointer present, and §4.2 puts a phone
  # in scope. The engaged rung is the strong one because the bar is a raised surface, and
  # A.2.2 gives that surface and a resting fill the same ramp step.
  defp control do
    [
      "min-h-target-touch min-w-target-touch flex shrink-0 items-center justify-center",
      "rounded-md text-on-surface-strong hover:bg-fill-subtle-strong",
      "disabled:text-on-surface-muted disabled:hover:bg-transparent"
    ]
  end

  # Complete literals: a class built from a value generates no rule and renders colourless.
  defp hue("video"), do: "text-class-video"
  defp hue("audio"), do: "text-class-audio"
  defp hue("image"), do: "text-class-image"
  defp hue("text"), do: "text-class-text"
  defp hue("software"), do: "text-class-software"
  defp hue("package"), do: "text-class-package"
end
