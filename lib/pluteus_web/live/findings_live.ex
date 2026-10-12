defmodule PluteusWeb.FindingsLive do
  @moduledoc """
  What a stage could not do, or would not guess about ([spec-04] §9, [spec-10] §16.1).

  A finding is the household's rather than a principal's, so this is one list and every
  member sees the same one. Clearing is attributed to whoever cleared it.

  Grouped by what went wrong, because a pass that could not do one thing to two hundred
  files records two hundred findings of one shape, and a list of them in order would
  bury the other two.
  """

  use PluteusWeb, :surface

  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Design.Glyphs
  alias Pluteus.Ingest
  alias Pluteus.Principals.Principal
  alias Pluteus.Repo
  alias PluteusWeb.Absence
  alias PluteusWeb.Chrome
  alias PluteusWeb.Interface

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    profile = %Profile{language: session["language"], assigner_id: session["assigner_id"]}

    {:ok,
     socket
     |> assign(:profile, profile)
     |> assign(:principal_name, principal_name(socket.assigns.principal_id, profile))
     |> assign(:contexts, session["contexts"] || %{})
     |> assign(:transport, Interface.transport(session))
     |> assign(:announcement, "")
     |> assign(:states, vocabulary())
     |> gathered()}
  end

  # §5.2's states with A.8.8's marker for each, assembled here because A.9.5 admits no
  # glyph name built in a template: a name assembled at render time is invisible to the
  # stylesheet's build and yields an element with no rule at all.
  #
  # *Held* leads, because the other seven are each a way of not being it.
  defp vocabulary do
    markers =
      Map.new(Glyphs.markers(), fn {state, _contour, _field, _mark} ->
        {String.replace(state, "-", "_"), "state-#{state}-mini"}
      end)

    [{"held", nil, "the value is there"}] ++
      for state <- Absence.states() do
        {String.replace(state, "_", " "), Map.fetch!(markers, state), Absence.words(state)}
      end
  end

  @impl Phoenix.LiveView
  def handle_event("clear", %{"id" => id}, socket) do
    case Ingest.clear_finding(id, socket.assigns.principal_id) do
      {:ok, _finding} ->
        {:noreply, socket |> gathered() |> assign(:announcement, "Cleared.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "That was not cleared: #{inspect(reason)}")}
    end
  end

  defp gathered(socket) do
    findings = Ingest.open_findings()

    socket
    |> assign(:findings, findings)
    |> assign(:groups, grouped(findings))
  end

  # Newest first within a group, and the fullest group first: what a person is being
  # asked to look at is whatever there is most of.
  defp grouped(findings) do
    findings
    |> Enum.group_by(&{&1.stage, &1.kind})
    |> Enum.map(fn {{stage, kind}, held} ->
      %{
        stage: stage,
        kind: kind,
        permanent?: Enum.all?(held, & &1.permanent),
        findings: Enum.sort_by(held, & &1.recorded_at, {:desc, DateTime}),
        count: length(held)
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp principal_name(principal_id, profile) do
    case Repo.get(Principal, principal_id) do
      %Principal{person_id: nil} -> nil
      %Principal{person_id: person_id} -> Resolution.resolve_many([person_id], profile)[person_id]
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Chrome.shell
      principal_name={@principal_name}
      contexts={@contexts}
      findings={length(@findings)}
      announcement={@announcement}
      socket={@socket}
      transport={@transport}
    >
      <div id="findings" class="mx-auto w-full max-w-5xl px-4 py-10 sm:px-6">
        <Layouts.flash_group flash={@flash} />

        <header class="mb-8">
          <h1 class="text-title-lg font-medium text-on-surface-strong">Findings</h1>
          <p class="mt-1 text-body-sm text-on-surface-muted">
            {length(@findings)} {if length(@findings) == 1, do: "is", else: "are"} uncleared.
          </p>
        </header>

        <p :if={@findings == []} class="text-body-md text-on-surface-muted">
          Nothing is outstanding.
        </p>

        <ul class="flex flex-col gap-3">
          <li :for={group <- @groups}>
            <.group group={group} />
          </li>
        </ul>

        <.vocabulary states={@states} />
      </div>
    </Chrome.shell>
    """
  end

  # §5.2's eight states, with A.8.8's marker for each of the seven that has one. It is
  # here because this is the surface a person comes to when something is not as they
  # expected, and the difference between *nobody looked* and *a tool tried and could
  # not* is the difference between waiting and acting.
  #
  # *Held* carries no marker, which A.8.8 makes an invariant rather than a convention: a
  # reader cannot tell it from a state nobody computed, so the one that stands for
  # nobody having looked has a mark of its own.
  attr :states, :list, required: true

  defp vocabulary(assigns) do
    ~H"""
    <section id="findings-vocabulary" aria-labelledby="vocabulary-heading" class="mt-10">
      <h2 id="vocabulary-heading" class="mb-1 text-title-md font-medium text-on-surface-strong">
        What a surface can say about a value
      </h2>
      <p class="mb-3 text-body-sm text-on-surface-muted">
        Eight states, and no surface may render two of them alike.
      </p>

      <dl class="grid gap-x-6 gap-y-2 sm:grid-cols-2">
        <div :for={{state, glyph, words} <- @states} class="flex items-center gap-3 py-1">
          <dt class="flex w-40 shrink-0 items-center gap-2">
            <.icon :if={glyph} name={glyph} class="shrink-0 text-on-surface-muted" />
            <span
              :if={!glyph}
              aria-hidden="true"
              class="size-5 shrink-0 rounded-full bg-fill-subtle"
            >
            </span>
            <span class="truncate text-body-sm text-on-surface-strong">{state}</span>
          </dt>
          <dd class="text-body-sm text-on-surface-muted">{words}</dd>
        </div>
      </dl>
    </section>
    """
  end

  attr :group, :map, required: true

  defp group(assigns) do
    ~H"""
    <details class={[
      "rounded-md",
      "border-[length:var(--sys-border-width-hairline)] border-border-subtle",
      "bg-surface-raised"
    ]}>
      <summary class="flex min-h-target-touch cursor-pointer list-none items-center gap-3 px-4 py-3">
        <.icon name="hero-exclamation-triangle-mini" class="shrink-0 text-status-warning" />

        <span class="flex min-w-0 grow flex-col">
          <span class="truncate text-body-md text-on-surface-strong">{@group.kind}</span>
          <span class="text-caption text-on-surface-muted">
            {@group.stage} · {recurs(@group.permanent?)}
          </span>
        </span>

        <span class="shrink-0 font-mono text-caption text-on-surface-muted">{@group.count}</span>
      </summary>

      <ul class="flex flex-col">
        <li :for={finding <- @group.findings}>
          <.finding finding={finding} />
        </li>
      </ul>
    </details>
    """
  end

  attr :finding, :map, required: true

  defp finding(assigns) do
    ~H"""
    <div class={[
      "flex flex-wrap items-start gap-3 px-4 py-3",
      "border-t-[length:var(--sys-border-width-hairline)] border-border-subtle"
    ]}>
      <span class="flex min-w-0 grow flex-col gap-1">
        <span class="font-mono text-caption text-on-surface-muted">
          {Calendar.strftime(@finding.recorded_at, "%-d %B %Y, %H:%M")}
        </span>

        <dl :if={@finding.detail != %{}} class="flex flex-col gap-0.5">
          <div :for={{key, value} <- Enum.sort(@finding.detail)} class="flex gap-2">
            <dt class="shrink-0 text-caption text-on-surface-muted">{key}</dt>
            <dd class="min-w-0 truncate text-caption text-on-surface-strong">{said(value)}</dd>
          </div>
        </dl>

        <span :if={@finding.location} class="truncate text-caption text-on-surface-muted">
          {@finding.location}
        </span>
      </span>

      <button
        type="button"
        phx-click="clear"
        phx-value-id={@finding.id}
        class={[
          "min-h-target-pointer shrink-0 rounded-md px-4",
          "border-[length:var(--sys-border-width-component)] border-border-strong",
          "text-body-sm text-on-surface-strong hover:bg-fill-subtle-strong"
        ]}
      >
        Clear
      </button>
    </div>
    """
  end

  # A finding that will be recorded again by the next pass is a different thing to attend
  # to from one that stands until a person says otherwise.
  defp recurs(true), do: "stands until cleared"
  defp recurs(false), do: "recorded again by the next pass"

  defp said(value) when is_list(value), do: Enum.map_join(value, ", ", &said/1)
  defp said(value) when is_binary(value), do: value
  defp said(value), do: inspect(value)
end
