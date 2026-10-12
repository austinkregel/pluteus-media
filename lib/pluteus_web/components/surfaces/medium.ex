defmodule PluteusWeb.Surfaces.Medium do
  @moduledoc """
  What every surface holding a medium of its own carries: the band naming the holding,
  and §12.3's controls.

  Shared so a player and a transport agree on what a seek step is and what a position
  reads as. §12.3 asks the same of both.
  """

  use PluteusWeb, :html

  alias Pluteus.Surfaces.Registry, as: Surfaces

  @doc """
  The kind, the name, and a way back.

  Back is the browser's own history rather than a link to one surface: a person reached
  this from wherever they reached it from, and a link that guessed would take them
  somewhere they had not been.
  """
  attr :name, :string, required: true
  attr :category, :string, required: true

  def band(assigns) do
    ~H"""
    <header class={[
      "flex shrink-0 flex-wrap items-center gap-4 px-4 py-4 sm:px-6",
      "border-b-[length:var(--sys-border-width-hairline)] border-border-subtle"
    ]}>
      <button
        type="button"
        onclick="history.back()"
        class={[
          "min-h-target-pointer shrink-0 rounded-md px-4",
          "border-[length:var(--sys-border-width-component)] border-border-strong",
          "text-body-md text-on-surface-strong hover:bg-fill-subtle-strong"
        ]}
      >
        Back
      </button>

      <div class="flex min-w-0 flex-col">
        <.kind category={@category} />
        <h1 class="truncate text-title-lg font-medium text-on-surface-strong">{@name}</h1>
      </div>
    </header>
    """
  end

  @doc """
  What kind of holding this is, in the household's word for it and under its own glyph.

  The glyph carries the category and the colour the broad class, which is the division
  §20 draws: twelve categories over five hues, because a hue groups and a glyph
  identifies.
  """
  attr :category, :string, required: true

  def kind(assigns) do
    ~H"""
    <span class="flex items-center gap-2 text-body-sm text-on-surface-muted">
      <.icon name={Surfaces.category_icon(@category).glyph} class={hue(@category)} />
      {Surfaces.category_icon(@category).name}
    </span>
    """
  end

  defp hue(category) do
    case Surfaces.category_icon(category).class do
      "video" -> "text-class-video"
      "audio" -> "text-class-audio"
      "image" -> "text-class-image"
      "text" -> "text-class-text"
      "software" -> "text-class-software"
      "package" -> "text-class-package"
    end
  end

  @doc """
  §12.3's controls, acting on the element the hook is pointed at.

  The position slider sits outside the toolbar (A.9.4): a slider consumes the arrow keys
  a toolbar navigates with. Each control is disabled until the hook reaches the medium
  and enables it, so one that cannot act never looks as though it can (§17.3).
  """
  attr :medium, :string, required: true
  attr :extent, :any, required: true
  attr :marks, :list, default: []

  def controls(assigns) do
    assigns = assign(assigns, :steps, Surfaces.seek_granularity("millisecond"))

    ~H"""
    <div
      id="player-transport"
      phx-hook="Player"
      phx-update="ignore"
      data-medium={@medium}
      data-small={@steps["small"]}
      data-large={@steps["large"]}
      class="flex shrink-0 flex-col gap-3"
    >
      <div class="flex items-center gap-3">
        <span
          id="player-elapsed"
          class="w-12 shrink-0 text-right font-mono text-caption text-on-surface-muted"
        >
          {clock(0)}
        </span>

        <div class="relative grow">
          <label for="player-position" class="sr-only">Position</label>
          <input
            type="range"
            id="player-position"
            min="0"
            max={@extent || 0}
            value="0"
            disabled
            aria-valuetext={spoken(0, @extent)}
            class="w-full accent-fill-solid"
          />

          <span
            :for={at <- @marks}
            aria-hidden="true"
            class="pointer-events-none absolute top-0 h-6 w-0.5 bg-border-strong"
            style={"left: #{at}%"}
          >
          </span>
        </div>

        <span
          id="player-remaining"
          class="w-12 shrink-0 font-mono text-caption text-on-surface-muted"
        >
          {clock(@extent)}
        </span>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <div
          id="player-controls"
          role="toolbar"
          aria-label="Transport"
          class="flex items-center gap-2"
        >
          <button
            type="button"
            disabled
            data-act="back"
            aria-label={"Back #{seconds(@steps["small"])} seconds"}
            class={control()}
          >
            <.icon name="back-10-mini" />
          </button>

          <button type="button" disabled data-act="play" aria-label="Play" class={accent()}>
            <.icon name="hero-play-mini" data-glyph="play" />
            <.icon name="hero-pause-mini" data-glyph="pause" class="hidden" />
          </button>

          <button
            type="button"
            disabled
            data-act="forward"
            aria-label={"Forward #{seconds(@steps["large"])} seconds"}
            class={control()}
          >
            <.icon name="forward-30-mini" />
          </button>
        </div>

        <button
          type="button"
          disabled
          data-act="mute"
          aria-label="Mute"
          aria-pressed="false"
          class={control()}
        >
          <.icon name="hero-speaker-wave-mini" />
        </button>

        <label for="player-volume" class="sr-only">Volume</label>
        <input
          type="range"
          id="player-volume"
          min="0"
          max="100"
          step="5"
          value="100"
          disabled
          aria-valuetext="100 per cent"
          class="w-24 accent-fill-solid"
        />

        <span class="grow"></span>

        <button
          type="button"
          disabled
          data-act="fullscreen"
          class={[
            "min-h-target-pointer shrink-0 rounded-md px-4",
            "border-[length:var(--sys-border-width-component)] border-border-strong",
            "text-body-md text-on-surface-strong hover:bg-fill-subtle-strong",
            "disabled:text-on-surface-muted disabled:opacity-100"
          ]}
        >
          Full screen
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Where each chapter begins, as a share of the whole.

  Nothing is placed against a length nobody recorded, since that would be a position
  this deployment invented.
  """
  @spec marks([map()], non_neg_integer() | nil) :: [float()]
  def marks(_chapters, nil), do: []
  def marks(_chapters, 0), do: []

  def marks(chapters, extent) do
    for %{"start_ms" => start} <- chapters,
        start > 0,
        start < extent,
        do: Float.round(start / extent * 100, 3)
  end

  @doc """
  A length said the way the client says it, so the two drawings agree.
  """
  @spec clock(non_neg_integer() | nil) :: String.t()
  def clock(nil), do: "--:--"

  def clock(milliseconds) do
    total = div(milliseconds, 1000)

    "#{div(total, 60)}:#{String.pad_leading(to_string(rem(total, 60)), 2, "0")}"
  end

  defp seconds(nil), do: 0
  defp seconds(milliseconds), do: div(milliseconds, 1000)

  defp spoken(position, nil), do: "#{clock(position)}, of a length not recorded"
  defp spoken(position, extent), do: "#{clock(position)} of #{clock(extent)}"

  defp control do
    [
      "min-h-target-touch min-w-target-touch flex shrink-0 items-center justify-center",
      "rounded-md text-on-surface-muted disabled:opacity-100"
    ]
  end

  defp accent do
    [
      "min-h-target-touch min-w-target-touch flex shrink-0 items-center justify-center",
      "rounded-full bg-fill-subtle text-on-surface-muted disabled:opacity-100"
    ]
  end
end
