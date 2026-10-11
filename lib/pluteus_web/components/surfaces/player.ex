defmodule PluteusWeb.Surfaces.Player do
  @moduledoc """
  The player: the surface a film, a television episode and a home video are presented on
  ([spec-10] §12.1).

  The picture is the page, and beside it the choices §12.2 keeps apart — which audio
  track and which subtitle track. They are separate states, so turning subtitles off
  does not forget which one was chosen.

  §11.2 has the box reserved at the ratio the bytes were measured at, and §20's assumed
  one for the category where nothing has probed them, rather than collapsing to zero
  and growing when the first frame decodes.
  """

  use PluteusWeb, :html

  alias Pluteus.Playback
  alias Pluteus.Presentation.Geometry
  alias PluteusWeb.Surfaces.Medium

  attr :work, :map, required: true
  attr :name, :string, required: true
  attr :category, :string, required: true
  attr :playable, :any, required: true
  attr :chosen, :map, required: true

  def surface(assigns) do
    assigns =
      assigns
      |> assign(:reserved, reserved(assigns.playable, assigns.category))
      |> assign(:streams, streams(assigns.playable))
      |> assign(:extent, extent(assigns.playable))

    ~H"""
    <div class="flex w-full flex-1 flex-col">
      <Medium.band name={@name} category={@category} />

      <div class="flex flex-1 flex-col lg:flex-row">
        <div class="flex min-w-0 flex-1 flex-col gap-3 p-4 sm:p-6">
          <.picture playable={@playable} reserved={@reserved} name={@name} />

          <Medium.controls
            :if={match?({:ok, _ready}, @playable)}
            medium="player-medium"
            extent={@extent}
            marks={Medium.marks(@streams.chapters, @extent)}
          />
        </div>

        <.beside streams={@streams} chosen={@chosen} />
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

  defp picture(assigns) do
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
        preload="metadata"
        aria-label={@name}
        class="size-full"
        src={~p"/assets/#{first_part(@playable).asset_id}/content"}
      >
      </video>
    </div>
    """
  end

  attr :streams, :map, required: true
  attr :chosen, :map, required: true

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
        kind="subtitle"
        heading="Subtitles"
        tracks={@streams.subtitle}
        chosen={@chosen.subtitle}
      />

      <.choice
        id="player-audio"
        kind="audio"
        heading="Audio"
        tracks={@streams.audio}
        chosen={@chosen.audio}
      />
    </aside>
    """
  end

  attr :id, :string, required: true
  attr :kind, :string, required: true
  attr :heading, :string, required: true
  attr :tracks, :list, required: true
  attr :chosen, :any, required: true

  defp choice(assigns) do
    ~H"""
    <section id={@id} aria-labelledby={"#{@id}-heading"}>
      <h2 id={"#{@id}-heading"} class="text-caption uppercase tracking-wide text-on-surface-muted">
        {@heading}
      </h2>

      <p :if={@tracks == []} class="mt-2 text-body-sm text-on-surface-muted">None held.</p>

      <ul :if={@tracks != []} class="mt-2 flex flex-col gap-1">
        <li :for={track <- @tracks}>
          <button
            type="button"
            aria-pressed={to_string(track.index == @chosen)}
            phx-click="choose-track"
            phx-value-kind={@kind}
            phx-value-index={track.index}
            class={[
              "flex min-h-target-pointer w-full items-center gap-2 rounded-md px-3 py-1 text-left",
              "hover:bg-fill-subtle-strong",
              track.index == @chosen && "bg-fill-subtle"
            ]}
          >
            <span class="flex min-w-0 grow flex-col">
              <span class="truncate text-body-sm text-on-surface-strong">{spoken(track)}</span>
              <span class="truncate text-caption text-on-surface-muted">{described(track)}</span>
            </span>
            <.icon
              :if={track.index == @chosen}
              name="hero-check-circle-mini"
              class="shrink-0 text-on-surface-strong"
            />
          </button>
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

  defp reserved({:ok, %{parts: [part | _rest]}}, category) do
    Geometry.reserve(Geometry.for_res([part.asset_id])[part.asset_id], category)
  end

  defp reserved({:error, _refusal}, category) do
    Geometry.reserve(nil, category)
  end

  defp streams({:ok, playable}), do: Playback.medium(playable)
  defp streams({:error, _refusal}), do: %{audio: [], subtitle: [], chapters: []}

  # The end of the region where the holding is carried by part of a larger medium, and
  # of the whole otherwise.
  defp extent({:error, _refusal}), do: nil
  defp extent({:ok, %{to_ms: to, from_ms: from}}) when is_integer(to), do: to - from

  defp extent({:ok, %{parts: parts}}) do
    durations = Enum.map(parts, & &1.duration_ms)

    if Enum.any?(durations, &is_nil/1), do: nil, else: Enum.sum(durations)
  end

  # A category §20 reserves nothing for leaves the box to the medium.
  defp box(nil), do: nil
  defp box(ratio), do: "aspect-ratio: #{ratio}"

  defp first_part({:ok, %{parts: [part | _rest]}}), do: part
end
