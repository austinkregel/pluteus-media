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

  alias Pluteus.Ingest.Registry
  alias Pluteus.Playback
  alias Pluteus.Presentation.Geometry
  alias PluteusWeb.Settings
  alias PluteusWeb.Surfaces.Medium

  attr :work, :map, required: true
  attr :name, :string, required: true
  attr :category, :string, required: true
  attr :playable, :any, required: true
  attr :chosen, :map, required: true
  attr :preferences, :map, required: true
  attr :refusal, :any, default: nil
  attr :trickplay, :any, default: nil

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
            trickplay={@trickplay}
          />

          <.delivery :if={match?({:ok, _ready}, @playable)} playable={@playable} />
          <.stopped :if={@refusal} refusal={@refusal} />
        </div>

        <.beside streams={@streams} chosen={@chosen} preferences={@preferences} />
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

  # What was handed to the client, which is all this deployment can state: the stored
  # bytes under the media type they are served as. Whether the browser then plays them is
  # the browser's answer and arrives as a failure or not at all, so saying so here would
  # be asserting an outcome nothing has established.
  attr :playable, :any, required: true

  defp delivery(assigns) do
    served = Registry.name_of_media_type(first_part(assigns.playable).media_type)

    assigns = assign(assigns, :served, served)

    ~H"""
    <p id="player-delivery" class="text-caption text-on-surface-muted">
      Served as held · {@served}
    </p>
    """
  end

  # The holding was served and the browser stopped. It is on this surface rather than in
  # a flash that goes away, because it is a fact about this holding on this device: the
  # bytes are held and this browser will not play them.
  attr :refusal, :map, required: true

  defp stopped(assigns) do
    ~H"""
    <div
      id="player-stopped"
      role="status"
      class={[
        "flex flex-col gap-1 rounded-md px-4 py-3",
        "border-[length:var(--sys-border-width-component)] border-border-strong",
        "bg-surface-raised"
      ]}
    >
      <p class="text-body-md text-on-surface-strong">{@refusal.said}</p>
      <p :if={@refusal.detail != ""} class="font-mono text-caption text-on-surface-muted">
        {@refusal.detail}
      </p>
    </div>
    """
  end

  attr :streams, :map, required: true
  attr :chosen, :map, required: true
  attr :preferences, :map, required: true

  defp beside(assigns) do
    assigns = assign(assigns, :captions, Settings.keys(:captions))

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
      <%!-- §12.2's three states, kept apart: whether subtitles are shown at all is not
            which one is chosen, and neither is which audio is playing. Turning them off
            is a setting of this principal's that outlives the holding, which is why it
            is held where §14.5 holds the rest of them. --%>
      <section id="player-shown" aria-labelledby="player-shown-heading">
        <h2
          id="player-shown-heading"
          class="mb-2 text-caption uppercase tracking-wide text-on-surface-muted"
        >
          Subtitles are shown
        </h2>
        <Settings.control
          key="subtitle_visibility"
          value={@preferences["subtitle_visibility"]}
          prefix="subtitle_"
        />
      </section>

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

      <%!-- §17.4: a caption's presentation is adjustable and persisted per principal. It
            names no property of it, so these four are the ones this deployment draws and
            §20 is where their values live. --%>
      <section id="player-captions" aria-labelledby="player-captions-heading">
        <h2
          id="player-captions-heading"
          class="mb-2 text-caption uppercase tracking-wide text-on-surface-muted"
        >
          Caption appearance
        </h2>
        <div class="flex flex-col gap-4">
          <Settings.control
            :for={key <- @captions}
            key={key}
            value={@preferences[key]}
            prefix="caption_"
          />
        </div>
      </section>
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
            id={"#{@id}-#{track.index}"}
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

  @doc """
  What a media element's own error code says, in words.

  The four are the element's whole vocabulary, so a code outside them is something this
  deployment has not met and is said as that rather than as nothing. The words are here
  because the code is the model's and §8.5 keeps that off a surface.
  """
  @spec refusal(integer() | nil) :: String.t()
  def refusal(1), do: "Playing this was stopped before it finished."
  def refusal(2), do: "The bytes stopped arriving part way through."
  def refusal(3), do: "This browser could not decode what was sent."
  def refusal(4), do: "This browser does not play what this is held as."

  def refusal(_unmet),
    do: "This browser stopped playing it, and said why in a way nothing here reads."
end
