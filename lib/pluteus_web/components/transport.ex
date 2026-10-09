defmodule PluteusWeb.Transport do
  @moduledoc """
  The persistent transport ([spec-10] §12.3).

  Rendered from `Pluteus.Playback.current/2`, which is the queue's own current entry, so
  the bar and the queue cannot disagree about what is playing. With nothing current there
  is no transport: a bar saying nothing is playing is a control for an affordance that
  does not exist.

  ## Every control states what it will do, not what is true

  §12.3 requires the play control's accessible name state "the action it will perform",
  so it reads *Play* while paused and *Pause* while playing. The same reading governs the
  mute control.

  ## The position slider

  It carries its minimum, maximum, current value and a human-readable value, and the
  readable one goes in `aria-valuetext` rather than in the accessible name: a name is
  announced once when the control is reached, and a value has to be announced each time
  it changes.

  Both of §20's granularities: `step` is the small one, which is one key press and so the
  one a person repeats, and the large one is a control of its own in each direction. §17.5
  forbids any function requiring a drag, and §12.3 forbids the slider being the only way
  to seek, so the large steps are buttons rather than a gesture.

  It is outside the live region, which §12.3 requires in those words: a position
  announced as it advanced would talk over everything else the region has to say.

  ## Volume is not a position

  Volume and mute are the client's own and reach no server. They are not consumption data
  and nothing about them belongs to the catalog, so they are rendered here and read by
  the media element beside them.

  ## What it does not carry, and why

  Skip intervals, the three track controls of §12.2 and full screen belong to the surface
  a medium is played on rather than to the bar that persists across every surface, and
  that surface's own board draws them. Playback speed is §12.3's "where the category
  carries spoken word", and no registry says which categories those are — §20 holds no
  such table, and naming them here would be the deployment inventing a vocabulary a
  registry is supposed to carry.
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

      <div class="flex items-center gap-3">
        <.standing_for showing={@showing} />

        <span class="flex min-w-0 grow flex-col">
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

        <.volume />
      </div>

      <.position
        showing={@showing}
        extent={@extent}
        steps={@steps}
        disabled?={@extent == nil or @refusal != nil}
      />
    </div>
    """
  end

  # Who it is by, then what it is. Both are said, because a glyph and a hue are carriers
  # §5.3 and A.2.6 each forbid being the only one, and who made something is the fact a
  # person wants beside its name.
  defp by(%{credited: [], category: category}), do: kind_of(category)

  defp by(%{credited: credited, category: category}),
    do: "#{Enum.join(credited, ", ")} · #{kind_of(category)}"

  defp kind_of(nil), do: Absence.words("not_yet_examined")
  defp kind_of(category), do: Surfaces.category_icon(category).name

  # The cover it is known by, and the glyph where there is none — in the hue of its broad
  # class, since A.2.6 has the glyph identify the category and the colour group it. A res
  # whose kind nothing records carries A.8.8's marker for that rather than an empty square.
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

  # A.9.3 makes the transport a toolbar, which is one tab stop its arrow keys move
  # within. The two sliders stay outside it for the reason A.9.4 gives of the position
  # one: a slider consumes the arrow keys a toolbar navigates with, and that is as true
  # of volume as it is of position.
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
        phx-click="transport-previous"
        disabled={@first?}
        aria-label="The entry before this one"
        class={control()}
      >
        <.icon name="previous-mini" />
      </button>

      <button
        type="button"
        phx-click="transport-play"
        disabled={@refused?}
        aria-label={if @playing?, do: "Pause", else: "Play"}
        class={control()}
      >
        <.icon name={if @playing?, do: "hero-pause-mini", else: "hero-play-mini"} />
      </button>

      <button
        type="button"
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

  # Volume reaches no server, so it is a plain input the media element beside it reads.
  # A step rather than a drag, because §17.5 forbids a function that requires one, and a
  # native range because A.2.7 assigns semantic colour from element semantics: a control
  # built from a generic element with a role attribute receives none.
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
    <div class="flex items-center gap-3">
      <span class="w-12 shrink-0 text-right font-mono text-caption text-on-surface-muted">
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

  # The element the hook drives. Its parts travel as data because a holding in several
  # files is one sequence: a position is against the whole, so which file carries it is
  # arithmetic over the parts and not something a single source could express.
  #
  # `data-playing` is what a person asked for and `data-position` where the queue says
  # they are, so the element follows the server rather than the server following it.
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

  # §12.4: the offer carries a visible interval before it acts and is cancellable, and
  # audio does not begin without a person having asked. So the interval is counted down
  # here and nothing starts until it runs out or the person says so.
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

      <button type="button" phx-click="transport-offer-take" class={control()}>
        <span class="px-2 text-body-sm">Play it now</span>
      </button>

      <button type="button" phx-click="transport-offer-cancel" class={control()}>
        <span class="px-2 text-body-sm">Stop here</span>
      </button>
    </div>
    """
  end

  attr :showing, :map, required: true

  defp queue(assigns) do
    ~H"""
    <section id="transport-queue" aria-label="The queue" class="max-h-48 overflow-y-auto">
      <ol class="flex flex-col">
        <li :for={{entry, index} <- Enum.with_index(@showing.queue)}>
          <button
            type="button"
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

  # The whole the position is measured along: spec-01 §8.4's recorded figure, which is
  # what §13.2's floor and ceiling are measured against too, so the slider and the
  # thresholds cannot disagree about how long something is. Where nothing recorded one
  # the slider says so rather than drawing a scale it cannot place a value on.
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

  # A position is spoken as a place in the whole, because a bare figure says nothing
  # about how far through anything is.
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

  # The touch floor rather than the pointer one. A.4.2 sizes a target for the coarsest
  # pointer present rather than the primary one, and §4.2 makes this one layout that
  # serves a phone — so nothing shrinks by default and a fine pointer gets a denser mode
  # by choosing one.
  defp control do
    [
      "min-h-target-touch min-w-target-touch flex shrink-0 items-center justify-center",
      "rounded-md text-on-surface-strong hover:bg-fill-subtle",
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
