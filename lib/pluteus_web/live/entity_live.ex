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

  alias Pluteus.Catalog.Addressing
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Res
  alias Pluteus.Lifecycle
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Registry
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

    representation =
      Representation.of(res, %Profile{
        language: session["language"],
        assigner_id: session["assigner_id"]
      })

    {:ok,
     socket
     |> assign(:res, res)
     |> assign(:principal_id, principal_id)
     |> assign(:representation, representation)
     |> assign(:noun, ComposedName.noun(res.kind))
     |> assign(:addresses, addresses(representation))
     |> assign(:medium, medium(res))
     |> assign(:address, session["address"])
     |> assign(:placed?, placed?(res, session["address"], session["unit"]))
     |> assign(:whole, session["whole"])
     |> assign(:announcement, "")}
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

  # §10.3: where the region cannot be placed the surface says so rather than landing at the
  # beginning. A region measured in a unit the res has no extent in is one of those: §8.4
  # expects the figure to be recorded, and nothing here may supply it.
  defp placed?(_res, nil, _unit), do: true
  defp placed?(_res, _address, nil), do: true

  defp placed?(res, _address, unit) do
    not is_nil(Addressing.get_extent(res.id, String.to_existing_atom(unit)))
  end

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

      <section
        :if={@medium.picture != [] or @medium.waveform}
        id="entity-medium"
        aria-labelledby="entity-medium-heading"
        class="mb-10"
      >
        <h2 id="entity-medium-heading" class="sr-only">The thing itself</h2>

        <img
          :if={@medium.picture != []}
          id="entity-picture"
          src={served(@medium, List.last(@medium.picture))}
          srcset={srcset(@medium)}
          sizes="(min-width: 48rem) 42rem, 100vw"
          width={List.last(@medium.picture).width}
          height={List.last(@medium.picture).height}
          alt=""
          class="w-full rounded-lg bg-surface-raised"
        />

        <canvas
          :if={@medium.waveform}
          id="entity-waveform"
          phx-hook="Waveform"
          data-src={served(@medium, @medium.waveform)}
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

  # §11.1: an artefact is asked for by profile name, at the URI its subject already has.
  defp served(medium, artefact), do: "#{medium.path}/#{artefact.profile}"

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
