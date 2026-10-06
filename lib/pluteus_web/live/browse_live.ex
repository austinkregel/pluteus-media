defmodule PluteusWeb.BrowseLive do
  @moduledoc """
  A browse mode's surface (spec-10 §9.2, §9.3).

  One LiveView for every mode, because §9.2 makes every mode resolve to one faceted
  surface and the modes differ in what they select rather than in what they are. The mode
  arrives as the route's `live_action`, so a mode gaining a surface is a route and a
  selection rather than another page.

  ## One surface, two phases

  With nothing narrowed the facet values *are* the content: the kinds, the doors into
  unfinished work, and the axes that cannot answer yet named and inert. Narrow it and the
  values recede and the rows take over, with the choice moving into the rail as a chip.
  That is one surface in two phases rather than a dashboard and a results page, which is
  what lets §9.3's counts mean the same thing on both.

  Only the unnarrowed phase renders here. The narrowed one is what the rows and the chips
  are, and neither exists yet, so what a narrowing does today is state the count it would
  leave rather than draw the result of it.

  ## What this does not do

  No rows, no chips, no lateral movement, no search results, no transport. The ordering
  basis is stated because §9.5 requires it of any surface that orders without a ranking
  spec, and the gateway orders its doors by count descending.
  """

  use PluteusWeb, :live_view

  alias Pluteus.Browse
  alias Pluteus.Browse.Query
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Principals.Principal
  alias Pluteus.Repo
  alias PluteusWeb.Chrome

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    profile = %Profile{language: session["language"], assigner_id: session["assigner_id"]}

    {:ok,
     socket
     |> assign(:profile, profile)
     |> assign(:principal_name, principal_name(socket.assigns.principal_id, profile))
     |> assign(:contexts, session["contexts"] || %{})
     |> assign(:announcement, "")}
  end

  # The query is read from the parameters on every navigation rather than held, because
  # §9.4 makes the narrowing part of the address: a surface that kept it in the socket
  # could not be linked to, reloaded or gone back to.
  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    mode = Atom.to_string(socket.assigns.live_action)

    case Query.parse(mode, params) do
      {:ok, query} ->
        {:noreply, assign(socket, :surface, Browse.surface(query, socket.assigns.principal_id))}

      {:error, refusal} ->
        {:noreply, socket |> put_flash(:error, refused(refusal)) |> assign(:surface, nil)}
    end
  end

  # §9.3 names what is wrong rather than answering an unnarrowed surface, which would
  # state a narrowing that did not happen.
  defp refused({:unknown_category, value}),
    do: "There is nothing here of a kind called #{value}."

  defp refused({:unknown_mode, mode}),
    do: "There is no way of looking at the catalogue called #{mode}."

  # §14.1 wants the name a person recognises, and a principal's name is its person's,
  # resolved like any other res's. A principal with no person of its own has none, and the
  # chrome says so rather than being handed a stand-in.
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
      mode={Atom.to_string(@live_action)}
      announcement={@announcement}
    >
      <div id="browse" class="mx-auto max-w-6xl px-4 py-10 sm:px-6">
        <Layouts.flash_group flash={@flash} />

        <header :if={@surface} class="mb-8">
          <h1 class="text-title-lg font-medium text-on-surface-strong">Everything</h1>
          <p class="mt-1 text-body-sm text-on-surface-muted">
            {@surface.total} {holdings(@surface.total)}, ordered by how many are behind each door
          </p>
        </header>

        <div :if={@surface} class="flex flex-col gap-10">
          <.kinds facet={@surface.facets["category"]} />
          <.unfinished doors={@surface.unfinished} />
          <.inert_axes facets={@surface.facets} />
        </div>
      </div>
    </Chrome.shell>
    """
  end

  defp holdings(1), do: "holding"
  defp holdings(_many), do: "holdings"

  # The kinds band: every category the catalogue holds, with what selecting it would
  # leave. Ordered by count descending, which the header states.
  attr :facet, :any, required: true

  defp kinds(%{facet: {:available, []}} = assigns) do
    ~H"""
    <section aria-labelledby="kinds-heading">
      <h2 id="kinds-heading" class="mb-3 text-title-md font-medium text-on-surface-strong">
        Kinds
      </h2>
      <p class="text-body-md text-on-surface-muted">
        Nothing is held yet, so there are no kinds to go by.
      </p>
    </section>
    """
  end

  defp kinds(%{facet: {:available, _values}} = assigns) do
    assigns = assign(assigns, :values, Enum.sort_by(elem(assigns.facet, 1), &(-elem(&1, 1))))

    ~H"""
    <section aria-labelledby="kinds-heading">
      <h2 id="kinds-heading" class="mb-3 text-title-md font-medium text-on-surface-strong">
        Kinds
      </h2>
      <ul class="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4">
        <li :for={{value, count} <- @values}>
          <.door at={~p"/everything?#{[category: value]}"} label={noun(value)} count={count} />
        </li>
      </ul>
    </section>
    """
  end

  # §9.2's Unfinished band. One door reports no figure, and that is §14.3 rather than an
  # omission, so its absence is stated where a count would be.
  attr :doors, :list, required: true

  defp unfinished(assigns) do
    ~H"""
    <section aria-labelledby="unfinished-heading">
      <h2 id="unfinished-heading" class="mb-3 text-title-md font-medium text-on-surface-strong">
        Unfinished
      </h2>
      <ul class="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <li :for={door <- @doors}>
          <.door
            at={door_at(door.bucket)}
            label={door_label(door.bucket)}
            count={door.count}
            open={door.any?}
          />
        </li>
      </ul>
    </section>
    """
  end

  defp door_label("nothing_you_have_looked_at"), do: "Nothing you have looked at"
  defp door_label("unverified"), do: "Unverified"
  defp door_label("no_date_recorded"), do: "No date recorded"
  defp door_label("needs_a_decision"), do: "Needs a decision"

  # Two of the four are about what a tool found rather than about the catalogue's shape,
  # and §16.1 gives findings their own surface, so those two lead there.
  defp door_at("unverified"), do: ~p"/findings"
  defp door_at("needs_a_decision"), do: ~p"/findings"
  defp door_at(_a_narrowing_with_no_surface_yet), do: nil

  # §9.3 requires a facet with no available values still be named and shown inert, and
  # §17.3 requires the control carry the reason. The reason is the facet's own, because
  # the axes are not waiting on the same thing.
  attr :facets, :map, required: true

  defp inert_axes(assigns) do
    ~H"""
    <section aria-labelledby="inert-heading">
      <h2 id="inert-heading" class="mb-3 text-title-md font-medium text-on-surface-strong">
        Not yet answerable
      </h2>
      <ul class="flex flex-col gap-2">
        <li :for={{axis, {:inert, why}} <- Enum.sort(@facets)}>
          <div class={[
            "rounded-md px-4 py-3",
            "border-[length:var(--sys-border-width-component)] border-border-subtle",
            "bg-surface-raised"
          ]}>
            <p class="text-body-md text-on-surface-muted">{axis_noun(axis)}</p>
            <p class="mt-1 text-body-sm text-on-surface-muted">{why}</p>
          </div>
        </li>
      </ul>
    </section>
    """
  end

  defp axis_noun("person"), do: "People"
  defp axis_noun("place"), do: "Places"
  defp axis_noun("decade"), do: "Decades"
  defp axis_noun("language"), do: "Languages"

  # A door with somewhere to go is a link; one without is rendered disabled carrying why,
  # which §17.3 requires of a control for an affordance that does not exist.
  attr :at, :string, default: nil
  attr :label, :string, required: true
  attr :count, :any, default: nil
  attr :open, :boolean, default: true

  defp door(%{at: nil} = assigns) do
    ~H"""
    <button
      type="button"
      disabled
      aria-describedby={"door-#{slug(@label)}-why"}
      class={[door_face(), "w-full text-left disabled:opacity-100"]}
    >
      <span class="grow text-body-md text-on-surface-strong">{@label}</span>
      <span :if={@count} class="font-mono text-caption text-on-surface-strong">{@count}</span>
    </button>
    <p id={"door-#{slug(@label)}-why"} class="sr-only">
      {@label} has no surface to open onto yet.
    </p>
    """
  end

  defp door(assigns) do
    ~H"""
    <a href={@at} class={door_face()}>
      <span class="grow text-body-md text-on-surface-strong">{@label}</span>
      <span :if={@count} class="font-mono text-caption text-on-surface-strong">{@count}</span>
    </a>
    """
  end

  defp door_face do
    [
      "min-h-target-touch flex items-center gap-3 rounded-md px-4",
      "border-[length:var(--sys-border-width-component)] border-border-subtle",
      "bg-surface-raised hover:bg-surface-overlay"
    ]
  end

  defp slug(label), do: label |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")

  # §8.5 forbids showing the model's own vocabulary, so a category reaches a surface as
  # the noun a person would use for it. Only the first character is raised:
  # `String.capitalize/1` lowers everything after it, which would undo a proper noun a
  # later category may well carry.
  defp noun(category) do
    <<first::utf8, rest::binary>> = String.replace(category, "_", " ")

    String.upcase(<<first::utf8>>) <> rest
  end
end
