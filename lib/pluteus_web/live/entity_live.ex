defmodule PluteusWeb.EntityLive do
  @moduledoc """
  The interface page every res that has one shares ([spec-10] §8.4, §9.1).

  §8.4 gives every such res one template and §10.1 forbids a second address for a res
  that already has one, so one module serves all ten kinds §9.1 names. The kind decides
  what a band holds rather than which page is rendered.

  A band with nothing in it is absent rather than empty (§8.4). An absent field is said
  in words where its value would have gone, so §5.2's seven absences reach a reader, and
  a screen reader, as content rather than as a gap. §8.5 keeps the model's vocabulary out
  of every label: the interface says versions, editions and copies.

  Every focusable carries a stable identity derived from what it points at, which §17.7
  requires because LiveView protects only a focused form input from a patch. The live
  region is rendered on every mount and is empty until something has happened.
  """

  use PluteusWeb, :surface

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Annotations
  alias Pluteus.Annotations.Derivation
  alias Pluteus.Browse
  alias Pluteus.Browse.Query
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Addressing
  alias Pluteus.Catalog.DeepLink
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Catalog.Selection
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Place
  alias Pluteus.Lifecycle
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Registry
  alias Pluteus.Principals.Principal
  alias Pluteus.Repo
  alias Pluteus.Representation
  alias Pluteus.Representation.ComposedName
  alias Pluteus.Serials
  alias Pluteus.Surfaces.Registry, as: Surfaces
  alias PluteusWeb.Absence
  alias PluteusWeb.BadRequestError
  alias PluteusWeb.Chrome
  alias PluteusWeb.GoneError
  alias PluteusWeb.Interface
  alias PluteusWeb.Members
  alias PluteusWeb.Native
  alias PluteusWeb.NotFoundError

  # §5.2's seven absences, each in words. A state with none raises rather than rendering
  # §8.4's band 5 is structure and band 6 is connections. §8.5 forbids the model's own
  # words as a label, so each relation is said the way the interface says it.
  @structure %{
    "work" => "A version of",
    "expressions" => "Versions",
    "manifestations" => "Editions",
    "manifestation" => "Edition",
    "items" => "Copies",
    "digital_items" => "Files held",
    "digital_item" => "File",
    "assets" => "Stored copies",
    "parts" => "Parts",
    "wholes" => "Part of",
    "aggregates" => "Collects",
    "aggregated_by" => "Collected in",
    "target" => "Addresses"
  }

  @connections %{
    "creators" => "Created by",
    "created" => "Created",
    "credited_as" => "Credited on",
    "names" => "Names"
  }

  @doc """
  Every relation the page places, with the band it goes in and the label it is said by.
  """
  @spec relations() :: %{String.t() => {1..7, String.t()}}
  def relations do
    Map.merge(
      Map.new(@structure, fn {relation, label} -> {relation, {5, label}} end),
      Map.new(@connections, fn {relation, label} -> {relation, {6, label}} end)
    )
  end

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    principal_id = socket.assigns.principal_id
    profile = %Profile{language: session["language"], assigner_id: session["assigner_id"]}

    {:ok,
     socket
     |> assign(:profile, profile)
     |> assign(:principal_id, principal_id)
     |> assign(:principal_name, principal_name(principal_id, profile))
     |> assign(:contexts, session["contexts"] || %{})
     |> assign(:findings, Ingest.open_finding_count())
     |> assign(:transport, Interface.transport(session))
     |> assign(:announcement, "")}
  end

  # The res is read here rather than at mount, because a live navigation from one holding
  # to another keeps this process and only the parameters change.
  #
  # The refusals are §9.1's: a selector is read before the res is looked up, since one
  # naming no type or invalid at the kind's level makes the request malformed whatever
  # the res's state. The representation's own path answers these as problem documents,
  # which is `PluteusWeb.Representation`'s half of the same address.
  #
  # The kind is read from the address rather than carried in the session, because §9.1
  # fixes it by the path and this is what runs when the path changes. A live session's
  # session is built once, by the request that established the socket, so a person
  # arriving here from a mode would be answered for whatever that page was — which for a
  # mode is no kind at all.
  @impl Phoenix.LiveView
  def handle_params(%{"id" => id} = params, uri, socket) do
    kind = kind!(uri)
    profile = socket.assigns.profile

    selector = selected!(kind, params)
    res = held!(id, kind)
    representation = Representation.of(res, profile)
    address = selector && address(kind, res, selector)
    unit = selector && unit(selector)
    extent = extent(res, unit)
    members = members(res, socket.assigns.principal_id, profile)

    {:noreply,
     socket
     |> assign(:res, res)
     |> assign(:representation, representation)
     |> assign(:annotations, annotations(res, profile))
     |> assign(:action, action(res, socket.assigns.principal_id, profile))
     |> assign(:surface_at, surface_at(res))
     |> assign(:noun, ComposedName.noun(res.kind))
     |> assign(:addresses, addresses(representation, profile))
     |> assign(:medium, medium(res))
     |> assign(:credits, credits(res, socket.assigns.principal_id, profile))
     |> assign(:members, members)
     |> assign(:members_word, members_word(res))
     |> assign(:carry_on, carry_on(members))
     |> assign(:address, address)
     |> assign(:placed?, is_nil(unit) or not is_nil(extent))
     |> assign(:mark, mark(address, extent))
     |> assign(:kind, kind)
     |> assign(:whole, "/#{Native.paths()[kind]}/#{res.id}")}
  end

  # A route reaching this view was built from the same table, so a path it cannot name is
  # a route that does not exist rather than a request to refuse.
  defp kind!(uri) do
    segments = uri |> URI.parse() |> Map.fetch!(:path) |> String.split("/", trim: true)

    Native.kind_at(segments) ||
      raise NotFoundError, message: "nothing of any kind is addressed at #{uri}"
  end

  # spec-01 §3.1's three agent kinds, which are the three a credit may name.
  @agents [:artist, :person, :collective_agent]

  # As many as stand in a band before the rest become a link to the whole of them, which
  # is what §9.4 licenses a bound for: everything left out is reachable by the same query
  # on the surface that lists holdings.
  @shown 12

  # §8.4's band 5 for an agent: what it is credited on, as the holdings a browse surface
  # would list rather than as every res a credit names. A release's tracks each credit
  # the artist, so a page listing them all would say the album twelve times and bury the
  # eleven other releases; the browse selection already answers which of them a household
  # is shown, and this is that selection narrowed to one agent.
  defp credits(%Res{kind: kind} = res, principal_id, profile) when kind in @agents do
    {:ok, query} = Query.parse("everything", %{"person" => res.id})

    Browse.surface(query, principal_id, profile, @shown)
  end

  defp credits(_another_kind, _principal_id, _profile), do: nil

  # §8.4's band 5 for a work that gathers others. A category the registry gives no word
  # for its members is a category that gathers none, so nothing is read for it: this is
  # the question asked of every work the page draws and it costs queries.
  defp members(%Res{kind: :work} = res, principal_id, profile) do
    case members_word(res) do
      nil -> []
      _word -> Serials.members(res.id, principal_id, profile)
    end
  end

  defp members(_another_kind, _principal_id, _profile), do: []

  defp members_word(%Res{kind: :work} = res) do
    case Catalog.category_of(res.id, Place.category_scheme()) do
      nil -> nil
      category -> Surfaces.category_icon(category).members
    end
  end

  defp members_word(_another_kind), do: nil

  # §8.4's band 2 for a work that gathers others. §8.1 resolves the action over the thing
  # itself, and a series is not a thing anybody plays — what there is to do with it is to
  # carry on with the member in progress, or to start the first one held.
  #
  # The member in progress is the one this principal has a position in, which §13.3 has
  # already ordered; where several are, the earliest in the arrangement is where a person
  # fell behind rather than where they most recently were.
  defp carry_on([]), do: nil

  defp carry_on(members) do
    held = Enum.filter(members, & &1.held?)

    Enum.find(held, &(&1.resumed_ms != nil)) || List.first(held)
  end

  defp carried(%{resumed_ms: nil, name: name}), do: "Start with #{name}"
  defp carried(%{name: name}), do: "Carry on with #{name}"

  defp selected!(kind, params) do
    case DeepLink.read(kind, params) do
      :none ->
        nil

      {:ok, selector} ->
        selector

      {:error, reason} ->
        raise BadRequestError, message: "the deep link's selector is refused: #{inspect(reason)}"
    end
  end

  defp held!(id, kind) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:live, %Res{kind: ^kind} = res} <- Lifecycle.state(uuid) do
      res
    else
      :error ->
        raise NotFoundError, message: "#{id} is not an identifier"

      {:recycled, _res, recycling} ->
        raise GoneError, message: "this is in the recycle bin until #{recycling.purge_after}"

      {:purged, _res, _tombstone} ->
        raise GoneError, message: "this was purged, and the identifier will not be reused"

      _absent_or_another_kind ->
        raise NotFoundError, message: "nothing of this kind is held at #{id}"
    end
  end

  defp address(kind, res, selector) do
    fields =
      Map.new(Map.delete(selector, :selector_type), fn {key, value} -> {to_string(key), value} end)

    Map.merge(fields, %{
      "type" => to_string(selector.selector_type),
      "link" => "/#{Native.paths()[kind]}/#{res.id}?#{DeepLink.query(selector)}"
    })
  end

  # The unit the region is measured in, which the page needs to ask whether the res has
  # an extent to place it against. A spatial, text-quote or track selector measures no
  # distance into anything and has none.
  # Kept as the unit `Pluteus.Catalog.Address` names, rather than said as a string and
  # read back as one: an atom rebuilt from a string is only there if something else has
  # already built it, so the round trip would make a unit the model names depend on what
  # the virtual machine has loaded.
  defp unit(selector), do: Address.unit(struct(Address, selector))

  # §14.1 wants the name a person recognises, and a principal's name is its person's,
  # resolved like any other res's at the boundary. A principal with no person of its own
  # has none, and the chrome says that rather than being handed a stand-in.
  defp principal_name(principal_id, profile) do
    case Repo.get(Principal, principal_id) do
      %Principal{person_id: nil} -> nil
      %Principal{person_id: person} -> resolved_name(person, profile)
    end
  end

  defp resolved_name(person, profile) do
    case Resolution.resolve_many([person], profile) do
      %{^person => nomen} -> nomen.nomen_string
      %{} -> nil
    end
  end

  # §10.2: the region is shown on the medium and not only named — a band across the
  # waveform, an outline on the picture. A selector whose medium this page does not draw
  # gets no mark, and the words in the region band are what carries it there.
  defp mark(nil, _extent), do: %{}

  defp mark(address, extent) do
    %{} |> span(address, extent) |> box(address)
  end

  defp span(mark, %{"type" => type} = address, %{magnitude: magnitude})
       when type in ~w(temporal spatiotemporal) and magnitude > 0 do
    Map.put(mark, :span, %{
      from: address["start_ms"] / magnitude,
      to: (address["end_ms"] || address["start_ms"]) / magnitude
    })
  end

  defp span(mark, _address, _extent), do: mark

  defp box(mark, %{"type" => type} = address) when type in ~w(spatial spatiotemporal) do
    Map.put(mark, :box, %{
      x: address["x_percent"],
      y: address["y_percent"],
      width: address["width_percent"],
      height: address["height_percent"]
    })
  end

  defp box(mark, _address), do: mark

  # §8.4's band 2: one primary action, resolved per §8.1, and the count of alternatives.
  #
  # Only a work has one. §8.1 defines the resolution over a work — to a specific expression
  # and digital item — and says nothing about resolving from an expression or a manifestation,
  # so for every other kind this band has nothing in it and §8.4 makes it absent.
  defp action(%Res{kind: :work, id: id}, principal_id, profile),
    do: Selection.for_principal(id, principal_id, profile)

  defp action(%Res{}, _principal_id, _profile), do: nil

  # Where §12.1 presents this holding, as the path §10.1 puts that surface at. A work
  # nothing has categorized is presented nowhere in particular, and one whose category
  # is presented by this page itself — a podcast listing its episodes, a game this
  # deployment does not run — has nowhere else to go.
  defp surface_at(%Res{kind: :work, id: id}) do
    case Catalog.category_of(id, Place.category_scheme()) do
      nil -> nil
      category -> Surfaces.surface_of(category)
    end
  end

  defp surface_at(%Res{}), do: nil

  # A clause per segment rather than one built from the string, because a verified route
  # is checked against the router only where it is written out. No catch-all, and a test
  # asserts these are exactly the segments the registry addresses, so a surface added
  # there fails here rather than linking somewhere that answers nothing.
  defp surface_path(id, "play"), do: ~p"/works/#{id}/play"
  defp surface_path(id, "read"), do: ~p"/works/#{id}/read"
  defp surface_path(id, "view"), do: ~p"/works/#{id}/view"

  # §8.4's band 7: what a person authored first and attributed, then what a tool derived,
  # labelled with the tool and version that produced it (spec-02 §4.1, §4.2). Only what
  # currently stands — a derived body whose tool has run again since is superseded and is
  # not this res's account of itself any more.
  defp annotations(res, profile) do
    {authored, derived} = Enum.split_with(Annotations.current_on(res.id), & &1.principal_id)

    %{authored: attributed(authored, profile), derived: labelled(derived)}
  end

  # spec-02 §10 makes an annotation household-visible, so who wrote it is shown. The name is
  # the author's own person resolved under the reader's profile, which is the same name band
  # 1 would give that person on their own page. A principal with no person of its own has no
  # name to attribute to, and none is invented.
  defp attributed([], _profile), do: []

  defp attributed(annotations, profile) do
    people =
      Repo.all(
        from p in Principal,
          where: p.id in ^Enum.map(annotations, & &1.principal_id),
          select: {p.id, p.person_id}
      )

    resolved =
      people
      |> Enum.map(&elem(&1, 1))
      |> Enum.reject(&is_nil/1)
      |> Resolution.resolve_many(profile)

    named = Map.new(people, fn {id, person} -> {id, person && resolved[person]} end)

    for annotation <- Enum.sort_by(annotations, & &1.id) do
      %{annotation: annotation, by: named[annotation.principal_id]}
    end
  end

  defp labelled([]), do: []

  defp labelled(annotations) do
    versions =
      Repo.all(
        from d in Derivation,
          join: v in assoc(d, :tool_version),
          where: d.id in ^Enum.map(annotations, & &1.derivation_id),
          select: {d.id, {v.tool, v.version, d.derived_at}}
      )
      |> Map.new()

    for annotation <- Enum.sort_by(annotations, & &1.id) do
      {tool, version, at} = Map.fetch!(versions, annotation.derivation_id)

      %{annotation: annotation, tool: tool, version: version, at: at}
    end
  end

  # §8.4's band 3 is the medium itself. What the subject has, rather than what its category
  # ought to have: the category-presentation registry §20 names is unseeded, so the
  # artefacts that exist are the only account of what can be shown. No image is generated to
  # stand for a holding that has none, and a band with nothing in it is absent.
  defp medium(res) do
    artefacts = Map.new(Presentation.for_subject(res.id), &{&1.profile, &1})

    %{
      picture: picture(artefacts),
      waveform: artefacts[Registry.waveform_overview()["name"]],
      path: "/#{Native.paths()[res.kind]}/#{res.id}/presentation"
    }
  end

  # The graded widths are one picture at several sizes, so they stand in for each other. A
  # key frame is a different picture — a frame of the moving image rather than a cover — so
  # it answers only where no graded width was derived, and never alongside them.
  defp picture(artefacts) do
    graded =
      Registry.image_profiles()
      |> Enum.map(&artefacts[&1["name"]])
      |> Enum.reject(&is_nil/1)

    case graded do
      [] -> List.wrap(artefacts[Registry.key_frame()["name"]])
      widths -> widths
    end
  end

  # How much of the res there is, in the unit the region is measured in. §10.3 turns on it:
  # without it the region cannot be placed, and §8.4 expects the figure to be recorded
  # rather than supplied here.
  defp extent(_res, nil), do: nil

  defp extent(res, unit), do: Addressing.get_extent(res.id, unit)

  # Each related res is linked at the URI spec-01 §9 gives it, under the name a person
  # knows it by. Both in a bounded number of queries for the page rather than one per
  # link, which is why they are gathered together: the kinds in one query, the names in
  # resolution's own batched pass, and the composed name for every res that pass returns
  # nothing displayable for.
  #
  # A kind with no interface page is still linked: §9.1 keeps it reachable as the
  # representation.
  defp addresses(representation, profile) do
    ids =
      for {_relation, %{"state" => "held", "value" => value}} <- representation["related"],
          id <- List.wrap(value),
          do: identifier(id)

    res = Repo.all(from r in Res, where: r.id in ^ids)
    paths = Native.paths()
    resolved = Resolution.visible_many(ids, profile)
    composed = ComposedName.for_many(Enum.reject(res, &resolved[&1.id]), profile)

    Map.new(res, fn %Res{id: id, kind: kind} ->
      {id,
       %{
         at: "/#{Map.fetch!(paths, kind)}/#{id}",
         page?: Native.negotiates?(kind),
         name: named(resolved[id], composed[id], profile)
       }}
    end)
  end

  # §5.3: a res resolution returns no displayable name for is named by §6.3. A reified
  # address and an annotation are in that position by construction, so the composed name
  # is the answer for them rather than a fallback.
  defp named(nil, composed, _profile) when is_binary(composed), do: composed

  defp named(nomens, _composed, profile) when is_list(nomens),
    do: Resolution.choose(nomens, profile).nomen_string

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Chrome.shell
      principal_name={@principal_name}
      contexts={@contexts}
      findings={@findings}
      announcement={@announcement}
      socket={@socket}
      transport={@transport}
    >
      <div id="entity" class="mx-auto max-w-measure px-4 py-10 sm:px-6">
        <Layouts.flash_group flash={@flash} />

        <header class="mb-10">
          <p class="text-body-sm text-on-surface-muted">{@noun}</p>
          <h1 id="entity-name" class="text-title-lg font-medium text-on-surface-strong">
            {name(@representation)}
          </h1>
          <p :if={composed?(@representation)} class="mt-1 text-body-sm text-on-surface-muted">
            No name of its own
          </p>
        </header>

        <section
          :if={@action}
          id="entity-action"
          aria-labelledby="entity-action-heading"
          class="mb-10"
        >
          <h2 id="entity-action-heading" class="sr-only">What you can do with this</h2>

          <div class="flex flex-wrap items-center gap-3">
            <.link
              :if={@surface_at}
              id="entity-primary-action"
              navigate={surface_path(@res.id, @surface_at)}
              class={[
                "rounded-full px-4 min-h-target-pointer inline-flex items-center",
                "text-body-md font-medium",
                "bg-fill-solid text-on-fill hover:bg-fill-solid-strong"
              ]}
            >
              {verb(@noun)}
            </.link>

            <.link
              :if={!@surface_at and @carry_on}
              id="entity-primary-action"
              navigate={Members.path(@carry_on)}
              class={[
                "rounded-full px-4 min-h-target-pointer inline-flex items-center",
                "text-body-md font-medium",
                "bg-fill-solid text-on-fill hover:bg-fill-solid-strong"
              ]}
            >
              {carried(@carry_on)}
            </.link>

            <button
              :if={!@surface_at and !@carry_on}
              id="entity-primary-action"
              type="button"
              disabled
              aria-describedby="entity-action-why"
              class={[
                "rounded-full px-4 min-h-target-pointer text-body-md font-medium",
                "bg-fill-subtle text-on-surface-muted",
                "border-[length:var(--sys-border-width-component)] border-border-component"
              ]}
            >
              {verb(@noun)}
            </button>

            <a
              :if={@action.alternatives > 0}
              id="entity-alternatives"
              href="#entity-band-5"
              class="underline text-body-sm"
            >
              {@action.alternatives} other {plural("version", @action.alternatives)}
            </a>
          </div>

          <p
            :if={!@surface_at and !@carry_on}
            id="entity-action-why"
            class="mt-2 text-body-sm text-on-surface-muted"
          >
            {why(@action)}
          </p>

          <p
            :if={@action.by == :nearest and @action.alternatives > 0}
            class="mt-1 text-body-sm text-on-surface-muted"
          >
            This is the version nearest what the work itself is, rather than one you asked for.
          </p>
        </section>

        <section
          :if={@medium.picture != [] or @medium.waveform}
          id="entity-medium"
          aria-labelledby="entity-medium-heading"
          class="mb-10"
        >
          <h2 id="entity-medium-heading" class="sr-only">The thing itself</h2>

          <div :if={@medium.picture != []} class="relative">
            <img
              id="entity-picture"
              src={served(@medium, List.last(@medium.picture))}
              srcset={srcset(@medium)}
              sizes="(min-width: 48rem) 42rem, 100vw"
              width={List.last(@medium.picture).width}
              height={List.last(@medium.picture).height}
              alt=""
              class="w-full rounded-lg bg-surface-raised"
            />
            <div
              :if={@mark[:box]}
              id="entity-region-outline"
              aria-hidden="true"
              class="absolute rounded-sm border-[length:var(--sys-border-width-component)] border-border-strong outline outline-offset-[-3px] outline-[color:var(--sys-color-surface-base)]"
              style={outline(@mark[:box])}
            >
            </div>
          </div>

          <canvas
            :if={@medium.waveform}
            id="entity-waveform"
            phx-hook="Waveform"
            data-src={served(@medium, @medium.waveform)}
            data-from={@mark[:span] && @mark[:span].from}
            data-to={@mark[:span] && @mark[:span].to}
            height="96"
            class="mt-4 w-full rounded-lg bg-surface-raised text-on-surface-strong"
            aria-label="The loudness of this recording over its length"
          >
          </canvas>
        </section>

        <section
          :if={@address}
          id="entity-region"
          aria-labelledby="entity-region-heading"
          class="mb-10 rounded-lg border-[length:var(--sys-border-width-component)] border-border-strong bg-surface-raised p-4"
        >
          <h2
            id="entity-region-heading"
            class="mb-1 text-title-md font-medium text-on-surface-strong"
          >
            What this link points at
          </h2>
          <p :if={@placed?} class="text-body-md text-on-surface-strong">{said_region(@address)}</p>
          <p :if={!@placed?} class="text-body-md text-on-surface-strong">
            This link points at {said_region(@address)}, which cannot be shown: how much of this
            there is has never been recorded, so the region cannot be placed within it.
          </p>
          <.link
            id="entity-whole"
            navigate={@whole}
            class="mt-3 inline-block underline text-body-sm"
          >
            Leave the region and see the whole
          </.link>
        </section>

        <section :if={facts(@representation) != []} aria-labelledby="entity-facts" class="mb-10">
          <h2 id="entity-facts" class="mb-2 text-title-md font-medium text-on-surface-strong">
            Facts
          </h2>
          <dl class="divide-y divide-border-subtle">
            <div :for={{name, field} <- facts(@representation)} class="flex gap-4 py-2">
              <dt class="w-48 shrink-0 text-body-sm text-on-surface-muted">{name}</dt>
              <dd class="text-body-sm text-on-surface-strong">
                <.value field={field} />
              </dd>
            </div>
          </dl>
        </section>

        <.credited :if={@credits} res={@res} surface={@credits} />

        <Members.band
          :if={@members_word}
          members={@members}
          word={@members_word}
          principal_name={@principal_name}
        />

        <.band
          :for={{band, heading} <- [{5, "Structure"}, {6, "Connections"}]}
          id={"entity-band-#{band}"}
          heading={heading}
          rows={in_band(@representation, band, @credits)}
          addresses={@addresses}
        />

        <section
          :if={@annotations.authored != [] or @annotations.derived != []}
          id="entity-annotations"
          aria-labelledby="entity-annotations-heading"
          class="mb-10"
        >
          <h2
            id="entity-annotations-heading"
            class="mb-2 text-title-md font-medium text-on-surface-strong"
          >
            What has been said about this
          </h2>

          <ul class="divide-y divide-border-subtle">
            <li :for={%{annotation: annotation, by: by} <- @annotations.authored} class="py-3">
              <p class="text-body-sm text-on-surface-strong">{said(annotation.body)}</p>
              <p class="text-caption text-on-surface-muted">
                {annotation.body_type} · {attribution(by)}
              </p>
            </li>

            <li
              :for={%{annotation: annotation, tool: tool, version: version} <- @annotations.derived}
              class="py-3"
            >
              <p class="text-body-sm text-on-surface-strong">{said(annotation.body)}</p>
              <p class="text-caption text-on-surface-muted">
                {annotation.body_type} · {tool} {version}
              </p>
            </li>
          </ul>
        </section>
      </div>
    </Chrome.shell>
    """
  end

  # What an agent is credited on, as the holdings themselves: the cover where one is
  # held, the name, and when it was issued. A bound of twelve, with everything beyond it
  # at the same query on the surface that lists holdings — which is the lateral movement
  # §9.4 requires of anything a band leaves out.
  attr :res, :map, required: true
  attr :surface, :map, required: true

  defp credited(assigns) do
    ~H"""
    <section id="entity-credits" aria-labelledby="entity-credits-heading" class="mb-10">
      <div class="mb-3 flex flex-wrap items-baseline gap-3">
        <h2 id="entity-credits-heading" class="text-title-md font-medium text-on-surface-strong">
          Credited on
        </h2>
        <span class="text-body-sm text-on-surface-muted">
          {@surface.total} {holdings(@surface.total)}
        </span>
        <span class="grow"></span>
        <.link
          :if={@surface.total > length(@surface.entries)}
          navigate={~p"/everything?#{[person: @res.id]}"}
          class="text-body-sm text-on-surface-strong underline"
        >
          All {@surface.total}
        </.link>
      </div>

      <p :if={@surface.entries == []} class="text-body-md text-on-surface-muted">
        Nothing this is credited on is held.
      </p>

      <ul :if={@surface.entries != []} class="grid grid-cols-2 gap-4 sm:grid-cols-4 lg:grid-cols-6">
        <li :for={id <- @surface.entries}>
          <.link navigate={~p"/works/#{id}"} class="group flex flex-col gap-2">
            <span class={[
              "flex aspect-square items-center justify-center overflow-hidden rounded-md",
              "border-[length:var(--sys-border-width-hairline)] border-border-subtle",
              "bg-surface-raised group-hover:border-border-strong"
            ]}>
              <img
                :if={@surface.covers[id]}
                src={~p"/manifestations/#{@surface.covers[id]}/presentation/image-320"}
                alt=""
                loading="lazy"
                class="size-full object-cover"
                onerror="this.remove()"
              />
              <span
                :if={!@surface.covers[id]}
                class="px-2 text-center text-caption text-on-surface-muted"
              >
                No cover is held for this.
              </span>
            </span>

            <span class="text-body-sm text-on-surface-strong">
              {Map.fetch!(@surface.names, id)}
            </span>
            <span :if={@surface.dates[id]} class="text-caption text-on-surface-muted">
              {@surface.dates[id]}
            </span>
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  defp holdings(1), do: "holding"
  defp holdings(_many), do: "holdings"

  attr :id, :string, required: true
  attr :heading, :string, required: true
  attr :rows, :list, required: true
  attr :addresses, :map, required: true

  defp band(assigns) do
    ~H"""
    <section :if={@rows != []} aria-labelledby={@id} class="mb-10">
      <h2 id={@id} class="mb-2 text-title-md font-medium text-on-surface-strong">{@heading}</h2>
      <dl class="divide-y divide-border-subtle">
        <div :for={{label, field} <- @rows} class="flex gap-4 py-2">
          <dt class="w-48 shrink-0 text-body-sm text-on-surface-muted">{label}</dt>
          <dd class="text-body-sm text-on-surface-strong">
            <.links
              :if={field["state"] == "held"}
              ids={List.wrap(field["value"])}
              addresses={@addresses}
            />
            <Absence.statement :if={field["state"] != "held"} state={field["state"]} />
          </dd>
        </div>
      </dl>
    </section>
    """
  end

  attr :ids, :list, required: true
  attr :addresses, :map, required: true
  attr :shown, :integer, default: @shown

  # A related res is said by the name a person knows it by, and linked at its own URI.
  # spec-07 §4.1 names it by identifier on the wire, which is the contract; §3.3 holds
  # that separate from what a surface the deployment draws owes a reader, and §8.2 asks
  # each line be described by what distinguishes it.
  #
  # The element's identity stays the identifier, which §17.7 needs stable across a patch.
  defp links(assigns) do
    assigns = assign(assigns, :all, length(assigns.ids))

    ~H"""
    <ul class="flex flex-col gap-1">
      <li :for={id <- @ids |> Enum.take(@shown) |> Enum.map(&identifier/1)}>
        <.related id={id} address={Map.fetch!(@addresses, id)} />
      </li>

      <%!-- §9.4 bounds an index this long provided nothing in it is reachable only here,
            and nothing is: every one of these is listed on the page of whatever presents
            it — a track on its release, a part on its whole. --%>
      <li :if={@all > @shown} class="text-body-sm text-on-surface-muted">
        and {@all - @shown} more
      </li>
    </ul>
    """
  end

  # A kind §9.1 names has a page in this live session, so reaching it keeps what is
  # playing. A kind that answers only the representation has no route here to navigate
  # to, and asking for one would leave a person on a page that never arrived.
  attr :id, :string, required: true
  attr :address, :map, required: true

  defp related(%{address: %{page?: true}} = assigns) do
    ~H"""
    <.link id={"entity-link-#{@id}"} navigate={@address.at} class="underline">
      {@address.name}
    </.link>
    """
  end

  defp related(assigns) do
    ~H"""
    <a id={"entity-link-#{@id}"} href={@address.at} class="underline">{@address.name}</a>
    """
  end

  attr :field, :map, required: true

  defp value(assigns) do
    ~H"""
    <Absence.field field={@field}>{said(@field["value"])}</Absence.field>
    """
  end

  # A related field's value is an identifier, or a map carrying one and its position.
  defp identifier(%{"id" => id}), do: id
  defp identifier(id) when is_binary(id), do: id

  defp said(value) when is_binary(value), do: value
  defp said(value) when is_number(value), do: to_string(value)
  defp said(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp said(value) when is_atom(value), do: to_string(value)
  defp said(value) when is_list(value), do: Enum.map_join(value, ", ", &said/1)
  defp said(%{} = value), do: Enum.map_join(value, ", ", fn {k, v} -> "#{k}: #{said(v)}" end)

  defp name(representation) do
    case representation["name"] do
      %{"state" => "held", "value" => value} -> value
      _absent -> representation["composed_name"] || Absence.words(representation["name"]["state"])
    end
  end

  defp composed?(representation) do
    representation["name"]["state"] != "held" and not is_nil(representation["composed_name"])
  end

  # A name where the author has a person of their own, and the fact that there is none where
  # they have not. §17.3 forbids asserting what has not been established, and a name is not
  # the deployment's to supply.
  defp attribution(nil), do: "by a principal with no person of its own"
  defp attribution(nomen), do: "by #{nomen.nomen_string}"

  # §17.3: a control for an affordance that does not exist is rendered disabled and carries a
  # description saying why. Said only where there is no surface to reach: a holding whose
  # category §12.1 presents somewhere has a link instead, and a reason beside a working
  # control would be a reason for nothing.
  defp why(%{digital_item: nil}),
    do: "No file is held for this."

  defp why(%{}), do: "Nothing has said what kind of thing this is, so nothing presents it."

  # §8.5 keeps the model's words out of a control's name, so the verb follows the noun band 1
  # said rather than the kind.
  defp verb(noun) when noun in ~w(recording album film episode), do: "Play"
  defp verb(_noun), do: "Open"

  defp plural(word, 1), do: word
  defp plural(word, _many), do: word <> "s"

  # §11.1: an artefact is asked for by profile name, at the URI its subject already has.
  defp served(medium, artefact), do: "#{medium.path}/#{artefact.profile}"

  # A spatial selector states its region in percentages, so the outline is placed in the
  # same terms and holds wherever the picture is drawn at whatever width. The second edge is
  # drawn inside the first in the base surface's tone, so the outline stays visible over a
  # light picture and a dark one alike.
  defp outline(%{x: x, y: y, width: width, height: height}) do
    "left: #{x}%; top: #{y}%; width: #{width}%; height: #{height}%"
  end

  # The width each graded artefact actually is, so the browser picks one from CSS pixels
  # times device pixel ratio and never wants an intermediate.
  defp srcset(medium) do
    Enum.map_join(medium.picture, ", ", &"#{served(medium, &1)} #{&1.width}w")
  end

  @doc """
  The region a deep link names, in words.

  §10.2 requires the region be shown and not merely scrolled to, since a recipient who
  cannot see what they were sent has not received it. A type with no words raises.
  """
  @spec said_region(map()) :: String.t()
  def said_region(%{"type" => "temporal"} = address), do: span(address)

  def said_region(%{"type" => "spatiotemporal"} = address),
    do: "#{span(address)}, in part of the picture"

  def said_region(%{"type" => "spatial"}), do: "part of the picture"
  def said_region(%{"type" => "page"} = address), do: "page #{address["page_number"]}"

  def said_region(%{"type" => "text_position"} = address),
    do: "#{address["text_unit"]}s #{address["start_offset"]} to #{address["end_offset"]}"

  def said_region(%{"type" => "text_quote"} = address),
    do: "the passage beginning “#{address["quote_exact"]}”"

  def said_region(%{"type" => "track"} = address),
    do: "the #{address["stream_language"]} #{address["stream_kind"]} track"

  defp span(address) do
    case address["end_ms"] do
      nil -> "#{clock(address["start_ms"])}"
      end_ms -> "#{clock(address["start_ms"])} to #{clock(end_ms)}"
    end
  end

  defp clock(milliseconds) do
    seconds = milliseconds / 1000
    minutes = seconds |> trunc() |> div(60)
    rest = :erlang.float_to_binary(seconds - minutes * 60, decimals: 1)

    "#{minutes}:#{String.pad_leading(rest, 4, "0")}"
  end

  defp facts(representation) do
    representation |> Map.fetch!("own") |> Enum.sort_by(&elem(&1, 0))
  end

  # A relation the page has already drawn is not listed again as identifiers: an agent's
  # credits are the band above, under the names and covers of the holdings they are on.
  defp in_band(representation, band, credits) do
    placed = relations()
    drawn = if credits, do: ["credited_as"], else: []

    for {relation, field} <- Map.fetch!(representation, "related"),
        relation not in drawn,
        {^band, label} <- [Map.fetch!(placed, relation)] do
      {label, field}
    end
    |> Enum.sort_by(&elem(&1, 0))
  end
end
