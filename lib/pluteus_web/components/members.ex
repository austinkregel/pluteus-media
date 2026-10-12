defmodule PluteusWeb.Members do
  @moduledoc """
  §8.4's band 5 for a work that gathers others: a series, a comic series, a podcast.

  The members are listed in the order the serial's own manifestation arranges them, and
  the number on each row is that arrangement rather than a property of the member — a
  source that numbers them differently records its own identifier and renumbers nothing
  (spec-01 §5.4).

  Three things a row may say that a list of links cannot. A member the household does not
  hold is drawn as not held, because the gap in a run of episodes is the thing a person is
  looking for and a list that left it out would show a run with no gap in it. A member
  resolution answers no name for carries §6.3's composed name with the absence of its own
  name stated beside it, never a number standing in for one. And what this principal has
  watched is said on the row, for that principal alone (§14.3).
  """

  use PluteusWeb, :html

  alias PluteusWeb.Surfaces.Medium

  attr :members, :list, required: true
  attr :word, :string, required: true
  attr :principal_name, :any, default: nil

  def band(%{members: []} = assigns), do: ~H""

  def band(assigns) do
    assigns =
      assigns
      |> assign(:held, Enum.count(assigns.members, & &1.held?))
      |> assign(:watched, Enum.count(assigns.members, & &1.watched?))

    ~H"""
    <section id="entity-members" aria-labelledby="entity-members-heading" class="mb-10">
      <div class={[
        "mb-4 flex flex-wrap items-baseline gap-4 pb-2",
        "border-b-[length:var(--sys-border-width-hairline)] border-border-subtle"
      ]}>
        <h2 id="entity-members-heading" class="text-title-md font-medium text-on-surface-strong">
          {String.capitalize(@word)}
        </h2>

        <span class="text-body-sm text-on-surface-muted">{said(@held, @word)}</span>

        <span class="grow"></span>

        <span :if={@watched > 0} class="text-caption text-on-surface-muted">
          What you have watched is yours alone
        </span>
      </div>

      <ol class="flex flex-col gap-1">
        <li :for={member <- @members}>
          <.member member={member} />
        </li>
      </ol>
    </section>
    """
  end

  attr :member, :map, required: true

  defp member(%{member: %{held?: false}} = assigns) do
    ~H"""
    <div
      id={"member-#{@member.manifestation_id}"}
      class={[
        "flex min-h-target-touch items-center gap-4 rounded-md px-3 py-2",
        "border-[length:var(--sys-border-width-component)] border-dashed border-border-strong",
        "bg-surface-raised"
      ]}
    >
      <.ordinal position={@member.position} />
      <span class="grow truncate text-body-md text-on-surface-muted">{@member.name}</span>
      <span class="shrink-0 text-body-sm text-on-surface-muted">Not held</span>
    </div>
    """
  end

  defp member(assigns) do
    ~H"""
    <.link
      id={"member-#{@member.manifestation_id}"}
      navigate={~p"/works/#{@member.work_id}"}
      class={[
        "flex min-h-target-touch items-center gap-4 rounded-md px-3 py-2",
        "hover:bg-fill-subtle-strong",
        @member.resumed_ms && "bg-fill-subtle"
      ]}
    >
      <.ordinal position={@member.position} />

      <img
        :if={@member.poster?}
        src={~p"/manifestations/#{@member.manifestation_id}/presentation/keyframe"}
        alt=""
        class="h-14 w-24 shrink-0 rounded-sm bg-surface-raised object-cover"
      />

      <span class="flex min-w-0 grow flex-col">
        <span class="truncate text-body-md text-on-surface-strong">{@member.name}</span>
        <span class="truncate text-body-sm text-on-surface-muted">{beneath(@member)}</span>
      </span>

      <span :if={@member.resumed_ms} class="shrink-0 text-body-sm font-medium text-on-surface-strong">
        Resume
      </span>

      <span
        :if={!@member.resumed_ms and @member.watched?}
        class="shrink-0 text-body-sm text-on-surface-muted"
      >
        Watched
      </span>
    </.link>
    """
  end

  attr :position, :any, required: true

  # A member the serial does not number carries no number: §5.4 makes the figure an
  # arrangement, and one invented here would be this deployment numbering what it holds.
  defp ordinal(assigns) do
    ~H"""
    <span class="w-8 shrink-0 text-right font-mono text-caption text-on-surface-muted">
      {@position}
    </span>
    """
  end

  # What is known about the member beside its name: when it was issued, how long it is,
  # how far into it this principal is, and whether it has a name of its own. Each is left
  # out where nothing recorded it rather than drawn as a dash.
  defp beneath(member) do
    [
      member.issued,
      reached(member),
      if(member.named?, do: nil, else: "No name of its own")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp reached(%{resumed_ms: nil, extent_ms: nil}), do: nil
  defp reached(%{resumed_ms: nil, extent_ms: extent}), do: Medium.clock(extent)

  defp reached(%{resumed_ms: at, extent_ms: nil}), do: "#{Medium.clock(at)} in"

  defp reached(%{resumed_ms: at, extent_ms: extent}),
    do: "#{Medium.clock(at)} of #{Medium.clock(extent)}"

  defp said(0, _word), do: "none held, in arrangement order"
  defp said(1, word), do: "1 #{singular(word)} held, in arrangement order"
  defp said(held, word), do: "#{held} #{word} held, in arrangement order"

  defp singular(word), do: String.trim_trailing(word, "s")
end
