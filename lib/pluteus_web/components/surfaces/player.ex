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

    ~H"""
    <div class="mx-auto flex w-full max-w-7xl flex-1 flex-col gap-4 px-4 py-6 sm:px-6">
      <header class="flex shrink-0 flex-wrap items-baseline gap-3">
        <h1 class="text-title-lg font-medium text-on-surface-strong">{@name}</h1>
        <span class="text-body-sm text-on-surface-muted">
          {Surfaces.category_icon(@category).name}
        </span>
      </header>

      <div class="flex flex-col gap-4 lg:flex-row">
        <div class="flex min-w-0 flex-1 flex-col gap-3">
          <.picture playable={@playable} reserved={@reserved} name={@name} />
          <.chapters chapters={@medium.chapters} />
        </div>

        <.beside medium={@medium} />
      </div>
    </div>
    """
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

  # §12.1 requires chapters of a player. A medium divided into none is not a medium
  # whose divisions nobody looked for: ffprobe reads them where a container states them,
  # so their absence is an answer and the band is simply not drawn.
  attr :chapters, :list, required: true

  defp chapters(%{chapters: []} = assigns), do: ~H""

  defp chapters(assigns) do
    ~H"""
    <section id="player-chapters" aria-labelledby="player-chapters-heading">
      <h2 id="player-chapters-heading" class="text-title-sm font-medium text-on-surface-strong">
        Chapters
      </h2>
      <ol class="mt-2 flex flex-col">
        <li
          :for={{chapter, number} <- Enum.with_index(@chapters, 1)}
          class={[
            "flex items-baseline gap-3 px-2 py-2",
            "border-b-[length:var(--sys-border-width-hairline)] border-border-subtle"
          ]}
        >
          <span class="w-6 shrink-0 font-mono text-caption text-on-surface-muted">{number}</span>
          <span class="grow truncate text-body-sm text-on-surface-strong">
            {chapter[:title] || chapter["title"] || "Chapter #{number}"}
          </span>
        </li>
      </ol>
    </section>
    """
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

  # A category §20 reserves nothing for leaves the box to the medium, which is the one
  # case §11.2 does not reach: there is no ratio to be wrong about.
  defp box(nil), do: nil
  defp box(ratio), do: "aspect-ratio: #{ratio}"

  defp first_part({:ok, %{parts: [part | _rest]}}), do: part
end
