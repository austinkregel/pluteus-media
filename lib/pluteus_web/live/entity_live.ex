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

  use PluteusWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Annotations
  alias Pluteus.Annotations.Derivation
  alias Pluteus.Catalog.Addressing
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Catalog.Selection
  alias Pluteus.Lifecycle
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Registry
  alias Pluteus.Principals.Principal
  alias Pluteus.Repo
  alias Pluteus.Representation
  alias Pluteus.Representation.ComposedName
  alias PluteusWeb.ForwardAuth
  alias PluteusWeb.Native

  # §5.2's seven absences, each in words. A state with none raises rather than rendering
  # as emptiness, which is the reading §5.1 says the catalog's holes must not get.
  @absences %{
    "not_held" => "not held",
    "not_yet_examined" => "not yet examined",
    "attempted_failed" => "a tool tried and could not establish this",
    "unknown" => "unknown — a source was consulted and stated none",
    "sought_not_found" => "looked for and not found",
    "known_unknowable" => "known to be unrecoverable",
    "known_absent" => "known to be absent"
  }

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
  The words an absent field is said in.
  """
  @spec absence(String.t()) :: String.t()
  def absence(state), do: Map.fetch!(@absences, state)

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
    %{"res_id" => res_id, "principal_id" => held} = session

    principal_id = established!(socket, held)
    {:live, res} = Lifecycle.state(res_id)

    profile = %Profile{language: session["language"], assigner_id: session["assigner_id"]}
    representation = Representation.of(res, profile)

    extent = extent(res, session["unit"])

    {:ok,
     socket
     |> assign(:annotations, annotations(res, profile))
     |> assign(:action, action(res, principal_id, profile))
     |> assign(:res, res)
     |> assign(:principal_id, principal_id)
     |> assign(:representation, representation)
     |> assign(:noun, ComposedName.noun(res.kind))
     |> assign(:addresses, addresses(representation))
     |> assign(:medium, medium(res))
     |> assign(:address, session["address"])
     |> assign(:placed?, is_nil(session["unit"]) or not is_nil(extent))
     |> assign(:mark, mark(session["address"], extent))
     |> assign(:whole, session["whole"])
     |> assign(:announcement, "")}
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

  defp extent(res, unit), do: Addressing.get_extent(res.id, String.to_existing_atom(unit))

  # Each related res is linked at the URI spec-01 §9 gives it, which needs its kind. One
  # query for the page rather than one per link, and a kind with no interface page is
  # still linked: §9.1 keeps it reachable as the representation.
  defp addresses(representation) do
    ids =
      for {_relation, %{"state" => "held", "value" => value}} <- representation["related"],
          id <- List.wrap(value),
          do: identifier(id)

    paths = Native.paths()

    from(r in Res, where: r.id in ^ids, select: {r.id, r.kind})
    |> Repo.all()
    |> Map.new(fn {id, kind} -> {id, "/#{Map.fetch!(paths, kind)}/#{id}"} end)
  end

  # Two mounts. The dead render is the request's, which `ForwardAuth` has already
  # established, and it carries the principal in the session. The connected mount is a
  # socket, whose only identity is the proxy's headers, so it establishes the principal
  # again from those. Disagreement raises: one document would be showing one principal's
  # page over another's connection.
  defp established!(socket, held) do
    case get_connect_info(socket, :x_headers) do
      nil ->
        held

      headers ->
        case ForwardAuth.principal(headers) do
          {:ok, %{id: ^held}} ->
            held

          {:ok, %{id: other}} ->
            raise "the socket is #{other}'s and the page is #{held}'s"

          {:error, type, detail} ->
            raise "the socket carries no principal: #{type}, #{detail}"
        end
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div id="entity" phx-hook="Focus" class="mx-auto max-w-4xl px-4 py-10 sm:px-6">
      <div
        id="entity-announcement"
        role="status"
        aria-live="polite"
        class="sr-only"
      >
        {@announcement}
      </div>

      <header class="mb-10">
        <p class="text-body-sm text-on-surface-muted">{@noun}</p>
        <h1 id="entity-name" class="text-title-lg font-semibold text-on-surface-strong">
          {name(@representation)}
        </h1>
        <p :if={composed?(@representation)} class="mt-1 text-body-sm text-on-surface-muted">
          Named by what it is made of, since nobody has named it.
        </p>
      </header>

      <section :if={@action} id="entity-action" aria-labelledby="entity-action-heading" class="mb-10">
        <h2 id="entity-action-heading" class="sr-only">What you can do with this</h2>

        <div class="flex flex-wrap items-center gap-3">
          <button
            id="entity-primary-action"
            type="button"
            disabled
            aria-describedby="entity-action-why"
            class={[
              "rounded-full px-4 min-h-target-pointer text-body-md font-semibold",
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

        <p id="entity-action-why" class="mt-2 text-body-sm text-on-surface-muted">
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
          class="mb-1 text-title-sm font-semibold text-on-surface-strong"
        >
          What this link points at
        </h2>
        <p :if={@placed?} class="text-body-md text-on-surface-strong">{said_region(@address)}</p>
        <p :if={!@placed?} class="text-body-md text-on-surface-strong">
          This link points at {said_region(@address)}, which cannot be shown: how much of this
          there is has never been recorded, so the region cannot be placed within it.
        </p>
        <a id="entity-whole" href={@whole} class="mt-3 inline-block underline text-body-sm">
          Leave the region and see the whole
        </a>
      </section>

      <section :if={facts(@representation) != []} aria-labelledby="entity-facts" class="mb-10">
        <h2 id="entity-facts" class="mb-2 text-title-sm font-semibold text-on-surface-strong">
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

      <section
        :if={@annotations.authored != [] or @annotations.derived != []}
        id="entity-annotations"
        aria-labelledby="entity-annotations-heading"
        class="mb-10"
      >
        <h2
          id="entity-annotations-heading"
          class="mb-2 text-title-sm font-semibold text-on-surface-strong"
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

      <.band
        :for={{band, heading} <- [{5, "Structure"}, {6, "Connections"}]}
        id={"entity-band-#{band}"}
        heading={heading}
        rows={in_band(@representation, band)}
        addresses={@addresses}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :heading, :string, required: true
  attr :rows, :list, required: true
  attr :addresses, :map, required: true

  defp band(assigns) do
    ~H"""
    <section :if={@rows != []} aria-labelledby={@id} class="mb-10">
      <h2 id={@id} class="mb-2 text-title-sm font-semibold text-on-surface-strong">{@heading}</h2>
      <dl class="divide-y divide-border-subtle">
        <div :for={{label, field} <- @rows} class="flex gap-4 py-2">
          <dt class="w-48 shrink-0 text-body-sm text-on-surface-muted">{label}</dt>
          <dd class="text-body-sm text-on-surface-strong">
            <.links
              :if={field["state"] == "held"}
              ids={List.wrap(field["value"])}
              addresses={@addresses}
            />
            <span :if={field["state"] != "held"} class="text-on-surface-muted">
              {absence(field["state"])}
            </span>
          </dd>
        </div>
      </dl>
    </section>
    """
  end

  attr :ids, :list, required: true
  attr :addresses, :map, required: true

  # A related res is said by its identifier, because §4.1's representation names it by
  # identifier and resolving every one of them here would be the embedding §4.1 forbids.
  # The identity is the identifier, which §17.7 needs to be stable across a patch.
  defp links(assigns) do
    ~H"""
    <ul class="flex flex-col gap-1">
      <li :for={id <- Enum.map(@ids, &identifier/1)}>
        <a id={"entity-link-#{id}"} href={Map.fetch!(@addresses, id)} class="underline">{id}</a>
      </li>
    </ul>
    """
  end

  attr :field, :map, required: true

  defp value(assigns) do
    ~H"""
    <span :if={@field["state"] == "held"}>{said(@field["value"])}</span>
    <span :if={@field["state"] != "held"} class="text-on-surface-muted">
      {absence(@field["state"])}
    </span>
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
      _absent -> representation["composed_name"] || absence(representation["name"]["state"])
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
  # description saying why. Nothing here plays or reads a holding yet, so the action says what
  # it would act on and that it cannot.
  defp why(%{digital_item: nil}),
    do: "The household describes this but holds no file of it, so there is nothing to open."

  defp why(%{}), do: "A file is held. Nothing in this deployment opens one yet."

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

  defp in_band(representation, band) do
    placed = relations()

    for {relation, field} <- Map.fetch!(representation, "related"),
        {^band, label} <- [Map.fetch!(placed, relation)] do
      {label, field}
    end
    |> Enum.sort_by(&elem(&1, 0))
  end
end
