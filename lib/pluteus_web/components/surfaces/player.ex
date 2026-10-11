defmodule PluteusWeb.Surfaces.Player do
  @moduledoc """
  The player: the surface a film, a television episode and a home video are presented on
  ([spec-10] §12.1).

  The picture is the page, and beside it the three choices §12.2 keeps apart — which
  audio track, which subtitle track, and whether subtitles are shown. They are three
  states and not one language preference, so turning subtitles off does not forget
  which one was chosen.

  ## Why a box is reserved before the bytes arrive

  §11.2 requires a surface reserve a box of the ratio the bytes were measured at, and
  §20's assumed one for the category where nothing has probed them, rather than
  collapsing to zero and growing when the first frame decodes. A page that reflows as
  its medium loads moves what a person was reaching for.

  ## What is drawn and does not yet act

  The medium carries the browser's own controls. §12.3's transport is the chrome's, and
  which of the two owns a surface that holds its own medium is not settled, so this
  draws no second set: two transports over one medium would leave a person pressing the
  one that does nothing.
  """

  use PluteusWeb, :html

  alias Pluteus.Playback
  alias Pluteus.Presentation.Geometry
  alias Pluteus.Surfaces.Registry, as: Surfaces

  attr :work, :map, required: true
  attr :name, :string, required: true
  attr :category, :string, required: true
  attr :playable, :any, required: true

  def surface(assigns) do
    assigns =
      assigns
      |> assign(:reserved, reserved(assigns.playable, assigns.category))
      |> assign(:medium, medium(assigns.playable))
      |> assign(:extent, extent(assigns.playable))
      |> assign(:steps, Surfaces.seek_granularity("millisecond"))

    ~H"""
    <div class="flex w-full flex-1 flex-col">
      <.heading name={@name} category={@category} />

      <div class="flex flex-1 flex-col lg:flex-row">
        <div class="flex min-w-0 flex-1 flex-col gap-3 p-4 sm:p-6">
          <.picture playable={@playable} reserved={@reserved} name={@name} />

          <.transport
            playable={@playable}
            extent={@extent}
            chapters={@medium.chapters}
            steps={@steps}
          />
        </div>

        <.beside medium={@medium} />
      </div>
    </div>
    """
  end

  # The kind, the name, and a way back. "Back" is the browser's own history rather than
  # a link to one surface: a person reached this from wherever they reached it from, and
  # a link that guessed would take them somewhere they had not been.
  attr :name, :string, required: true
  attr :category, :string, required: true

  defp heading(assigns) do
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
        <span class="flex items-center gap-2 text-body-sm text-on-surface-muted">
          <.icon name={Surfaces.category_icon(@category).glyph} class={hue(@category)} />
          {Surfaces.category_icon(@category).name}
        </span>
        <h1 class="truncate text-title-lg font-medium text-on-surface-strong">{@name}</h1>
      </div>
    </header>
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

  attr :playable, :any, required: true
  attr :reserved, :any, required: true
  attr :name, :string, required: true

  defp picture(%{playable: {:error, _refusal}} = assigns) do
    ~H"""
    <div
      id="player-refusal"
      class={[
        "flex items-center justify-center rounded-md p-10",
        "border-[length:var(--sys-border-width-component)] border-border-strong",
        "bg-surface-raised"
      ]}
      style={box(@reserved)}
    >
      <p class="max-w-measure text-body-md text-on-surface-muted">
        {Playback.why(elem(@playable, 1))}
      </p>
    </div>
    """
  end

  defp picture(%{playable: {:ok, _ready}} = assigns) do
    ~H"""
    <div
      id="player-picture"
      class={[
        "relative w-full overflow-hidden rounded-md",
        "border-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-base"
      ]}
      style={box(@reserved)}
    >
      <video
        id="player-medium"
        controls
        preload="metadata"
        aria-label={@name}
        class="size-full"
        src={~p"/assets/#{first_part(@playable).asset_id}/content"}
      >
      </video>
    </div>
    """
  end

  # §12.3's controls, acting on the medium above them. The position slider sits outside
  # the toolbar (A.9.4): a slider consumes the arrow keys a toolbar navigates with.
  #
  # Nothing here is wired to the medium yet, so every control is disabled and says why
  # rather than sitting live and doing nothing (§17.3).
  attr :playable, :any, required: true
  attr :extent, :any, required: true
  attr :chapters, :list, required: true
  attr :steps, :map, required: true

  defp transport(%{playable: {:error, _refusal}} = assigns), do: ~H""

  defp transport(assigns) do
    ~H"""
    <div id="player-transport" class="flex shrink-0 flex-col gap-3">
      <.position extent={@extent} chapters={@chapters} />

      <div class="flex flex-wrap items-center gap-2">
        <div
          id="player-controls"
          role="toolbar"
          aria-label="Transport"
          aria-describedby="player-controls-why"
          class="flex items-center gap-2"
        >
          <button
            type="button"
            disabled
            aria-label={"Back #{seconds(@steps["small"])} seconds"}
            class={control()}
          >
            <.icon name="back-10-mini" />
          </button>

          <button type="button" disabled aria-label="Play" class={accent()}>
            <.icon name="hero-play-mini" />
          </button>

          <button
            type="button"
            disabled
            aria-label={"Forward #{seconds(@steps["large"])} seconds"}
            class={control()}
          >
            <.icon name="forward-30-mini" />
          </button>
        </div>

        <button type="button" disabled aria-label="Mute" aria-pressed="false" class={control()}>
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

        <span :if={@chapters != []} class="text-body-sm text-on-surface-muted">
          {length(@chapters)} {if length(@chapters) == 1, do: "chapter", else: "chapters"}
        </span>

        <button
          type="button"
          disabled
          class={[
            "min-h-target-pointer shrink-0 rounded-md px-4",
            "border-[length:var(--sys-border-width-component)] border-border-strong",
            "text-body-md text-on-surface-muted disabled:opacity-100"
          ]}
        >
          Full screen
        </button>
      </div>

      <p id="player-controls-why" class="text-body-sm text-on-surface-muted">
        The medium carries the browser's own controls. These act on nothing yet.
      </p>
    </div>
    """
  end

  # §12.1 requires chapters of a player, and the slider is where they are. A medium
  # divided into none is not one whose divisions nobody looked for: ffprobe reads them
  # wherever a container states them, so their absence is an answer and no mark is drawn.
  attr :extent, :any, required: true
  attr :chapters, :list, required: true

  defp position(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <span class="w-12 shrink-0 text-right font-mono text-caption text-on-surface-muted">
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
          :for={at <- marks(@chapters, @extent)}
          aria-hidden="true"
          class="pointer-events-none absolute top-0 h-6 w-0.5 bg-border-strong"
          style={"left: #{at}%"}
        >
        </span>
      </div>

      <span class="w-12 shrink-0 font-mono text-caption text-on-surface-muted">
        {clock(@extent)}
      </span>
    </div>
    """
  end

  # Where each chapter begins, as a share of the whole. Nothing is drawn without a
  # measured extent: a mark placed against a length nobody recorded would be a position
  # this deployment invented.
  defp marks(_chapters, nil), do: []
  defp marks(_chapters, 0), do: []

  defp marks(chapters, extent) do
    for %{"start_ms" => start} <- chapters,
        start > 0,
        start < extent,
        do: Float.round(start / extent * 100, 3)
  end

  defp seconds(nil), do: 0
  defp seconds(milliseconds), do: div(milliseconds, 1000)

  defp clock(nil), do: "--:--"

  defp clock(milliseconds) do
    total = div(milliseconds, 1000)

    "#{div(total, 60)}:#{String.pad_leading(to_string(rem(total, 60)), 2, "0")}"
  end

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

  # §12.2's three controls, each its own state. Drawn beside the picture at the width
  # the board gives them and beneath it where there is none.
  attr :medium, :map, required: true

  defp beside(assigns) do
    ~H"""
    <aside
      id="player-tracks"
      aria-label="Audio and subtitles"
      class={[
        "flex w-full shrink-0 flex-col gap-6 rounded-md p-4 lg:w-88",
        "border-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-raised"
      ]}
    >
      <.choice
        id="player-subtitles"
        heading="Subtitles"
        tracks={@medium.subtitle}
        absent="No subtitle track is held with this, so there is nothing to show."
      />

      <.choice
        id="player-audio"
        heading="Audio"
        tracks={@medium.audio}
        absent="No audio track is held with this."
      />
    </aside>
    """
  end

  # A list of what may be chosen, or the words saying none is held. §17.3 keeps a control
  # for an affordance that does not exist disabled and carrying why, which for a track
  # list is the list saying what it is a list of and that it is empty.
  attr :id, :string, required: true
  attr :heading, :string, required: true
  attr :tracks, :list, required: true
  attr :absent, :string, required: true

  defp choice(assigns) do
    ~H"""
    <section id={@id} aria-labelledby={"#{@id}-heading"}>
      <h2
        id={"#{@id}-heading"}
        class="text-caption uppercase tracking-wide text-on-surface-muted"
      >
        {@heading}
      </h2>

      <p :if={@tracks == []} class="mt-2 text-body-sm text-on-surface-muted">{@absent}</p>

      <ul :if={@tracks != []} class="mt-2 flex flex-col gap-1">
        <li :for={track <- @tracks}>
          <span class={[
            "flex min-h-target-pointer flex-col justify-center rounded-md px-3 py-1",
            track.default? && "bg-fill-subtle"
          ]}>
            <span class="text-body-sm text-on-surface-strong">{spoken(track)}</span>
            <span class="text-caption text-on-surface-muted">{described(track)}</span>
          </span>
        </li>
      </ul>
    </section>
    """
  end

  # A language nothing recorded is said as that rather than guessed from the file's
  # order: spec-01 §7.2 forbids inferring one.
  defp spoken(%{language: nil}), do: "A language nothing recorded"
  defp spoken(%{language: language}), do: language

  defp described(track) do
    [track.codec, track.channel_layout, track.default? && "the default track"]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join(" · ")
  end

  # §11.2's reserved box: the ratio the bytes were measured at, and §20's assumed one
  # for the category where nothing has probed them.
  defp reserved({:ok, %{parts: [part | _rest]}}, category) do
    Geometry.reserve(Geometry.for_res([part.asset_id])[part.asset_id], category)
  end

  defp reserved({:error, _refusal}, category) do
    Geometry.reserve(nil, category)
  end

  # Nothing to play is nothing to describe, and the refusal already says why.
  defp medium({:ok, playable}), do: Playback.medium(playable)
  defp medium({:error, _refusal}), do: %{audio: [], subtitle: [], chapters: []}

  # The end of the region where the holding is carried by part of a larger medium, and
  # of the whole otherwise. A single part states its own length to the client, so the
  # sequence has none recorded and the slider says so rather than claiming a figure.
  defp extent({:error, _refusal}), do: nil
  defp extent({:ok, %{to_ms: to, from_ms: from}}) when is_integer(to), do: to - from

  defp extent({:ok, %{parts: parts}}) do
    durations = Enum.map(parts, & &1.duration_ms)

    if Enum.any?(durations, &is_nil/1), do: nil, else: Enum.sum(durations)
  end

  # A category §20 reserves nothing for leaves the box to the medium, which is the one
  # case §11.2 does not reach: there is no ratio to be wrong about.
  defp box(nil), do: nil
  defp box(ratio), do: "aspect-ratio: #{ratio}"

  defp first_part({:ok, %{parts: [part | _rest]}}), do: part
end
