defmodule Pluteus.Representation do
  @moduledoc """
  What the native API says about a res (spec-07 §4.1): its identifier and kind,
  its preferred name under a resolution profile, every nomen it carries, the
  identifiers of what it is related to by each relationship, what its kind
  records of its own, and its lifecycle state.

  A representation names related res by identifier and never embeds one. A
  related res may be recycled or purged, and an embedded copy would carry its
  state stale; a client that needs it asks for it, and learns where it stands.

  **Every field carries a value and a state** (spec-07 §4.1), and a field is never
  carried by its omission. `Pluteus.Representation.Field` is the term and
  `Pluteus.Representation.Absence` decides which of spec-10 §5.2's states a field
  with no value is in.

  `related` and `own` are namespaces rather than fields: they carry no state of
  their own, and every leaf inside them carries one. Field names are flat and
  unique within a kind, so an absence asserted about `creators` needs no path.

  The envelope — the identifier, the kind and the lifecycle state — is not a field
  and carries no state. Each is a property of the row's existence rather than
  something the household may or may not know.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Annotations
  alias Pluteus.Annotations.Annotation
  alias Pluteus.Annotations.Derivation
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Aggregation
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.AssetRole
  alias Pluteus.Catalog.Credit
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Item
  alias Pluteus.Catalog.ManifestationPart
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Catalog.WorkCreator
  alias Pluteus.Catalog.WorkPart
  alias Pluteus.Ingest.Place
  alias Pluteus.Presentation.Geometry
  alias Pluteus.Repo
  alias Pluteus.Representation.Absence
  alias Pluteus.Representation.ComposedName
  alias Pluteus.Representation.Field

  @measurements "measurements"

  @doc """
  The representation of a live res.
  """
  @spec of(Res.t(), Profile.t()) :: map()
  def of(%Res{} = res, %Profile{} = profile) do
    [representation] = of_many([res], profile)
    representation
  end

  @doc """
  The representations of many live res, in the order given.

  The evidence spec-10 §5.2 reads and the derived measurements it reports are
  gathered once for the whole page, so a collection costs a bounded number of
  queries for them however many res it holds.
  """
  @spec of_many([Res.t()], Profile.t()) :: [map()]
  def of_many(res_list, %Profile{} = profile) do
    res_ids = Enum.map(res_list, & &1.id)
    evidence = Absence.for_res(res_ids)
    measurements = Annotations.current_bodies(res_ids, @measurements)
    categories = Catalog.categories_of_many(res_ids)

    # [spec-10] §11.2 requires a visual res's dimensions in this call, so a surface
    # can reserve a box before it asks for any bytes. Where no probe has run the ratio
    # to reserve is §20's for the category, which lives on the work (spec-04 §6.3), so
    # the work is reached for the whole page at once.
    geometry = Geometry.for_res(res_ids)
    works = Catalog.works_of_many(res_ids)
    work_categories = Catalog.categories_of_many(Map.values(works))

    # Both reads are per profile: §7.3 makes a non-null assigner a name specific to
    # that agent, so one person's word for a thing never reaches another.
    resolved = Resolution.resolve_many(res_ids, profile)
    nomens = Resolution.visible_many(res_ids, profile)

    # §6.3 composes a name only for a res resolution answered nothing for.
    composed =
      res_list
      |> Enum.reject(&Map.has_key?(resolved, &1.id))
      |> ComposedName.for_many(profile)

    Enum.map(res_list, fn res ->
      context = %{
        evidence: Map.fetch!(evidence, res.id),
        measurements: Map.get(measurements, res.id, %{}),
        categories: Map.get(categories, res.id, []),
        geometry: geometry[res.id],
        work_category: work_category(works[res.id], work_categories),
        resolved: resolved[res.id],
        nomens: Map.get(nomens, res.id, []),
        composed: composed[res.id]
      }

      one(res, context)
    end)
  end

  defp one(%Res{} = res, context) do
    %{
      "id" => res.id,
      "kind" => res.kind,
      "state" => "live",
      "name" => Field.of(name(context.resolved), absent(context, "name")),
      "nomens" => Field.of(Enum.map(context.nomens, &nomen/1), absent(context, "nomens")),
      "categories" =>
        Field.of(
          Enum.map(context.categories, &category/1),
          absent(context, "categories")
        ),
      "geometry" => Field.of(geometry(context.geometry), absent(context, "geometry")),
      "related" => related(res, context),
      "own" => own(res, context)
    }
    |> put_composed_name(context.composed)
    |> put_reserved_ratio(context)
  end

  # §6.3 makes the composed name the surface's own rather than a field of the res,
  # so it carries no state and the key is present exactly where there is one.
  defp put_composed_name(representation, nil), do: representation

  defp put_composed_name(representation, composed),
    do: Map.put(representation, "composed_name", composed)

  # §11.2's ratio to reserve, which is the surface's own like the composed name: the
  # measured one where the bytes have been probed, and §20's for the category where
  # they have not. It carries no state, because it is always answerable — that is the
  # whole point of it, since a tile with no ratio collapses to nothing.
  defp put_reserved_ratio(representation, context) do
    case Geometry.reserve(context.geometry, context.work_category) do
      nil -> representation
      ratio -> Map.put(representation, "reserve_aspect_ratio", ratio)
    end
  end

  defp work_category(nil, _work_categories), do: nil

  defp work_category(work_id, work_categories) do
    work_categories
    |> Map.get(work_id, [])
    |> Enum.find_value(&if(&1.scheme == Place.category_scheme(), do: &1.value))
  end

  defp absent(context, field, otherwise \\ :not_yet_examined),
    do: Absence.state(context.evidence, field, otherwise)

  # §11.2's dimensions and the ratio that follows from them. A res nobody has probed
  # reports *not yet examined* rather than a zero-sized box.
  defp geometry(nil), do: nil

  defp geometry(%{width: width, height: height, aspect_ratio: aspect_ratio}),
    do: %{"width" => width, "height" => height, "aspect_ratio" => aspect_ratio}

  defp name(nil), do: nil
  defp name(%Nomen{nomen_string: nomen_string}), do: nomen_string

  defp nomen(%Nomen{} = n) do
    Map.take(n, [
      :id,
      :nomen_string,
      :language,
      :script,
      :scheme,
      :context_of_use,
      :assigner_id,
      :provenance
    ])
  end

  defp category(category), do: Map.take(category, [:scheme, :value, :provenance])

  defp related(%Res{kind: :work, id: id}, context) do
    %{
      "expressions" =>
        field(ids(from e in Expression, where: e.work_id == ^id, select: e.id), context,
          as: "expressions"
        ),
      "creators" =>
        field(ids(from c in WorkCreator, where: c.work_id == ^id, select: c.agent_id), context,
          as: "creators"
        ),
      "parts" =>
        field(ids(from p in WorkPart, where: p.whole_id == ^id, select: p.part_id), context,
          as: "parts"
        ),
      "wholes" =>
        field(ids(from p in WorkPart, where: p.part_id == ^id, select: p.whole_id), context,
          as: "wholes"
        )
    }
  end

  defp related(%Res{kind: :expression, id: id}, context) do
    %{
      # LRM-R2 binds an expression to exactly one work (spec-01 §6.1), so this is
      # a property of the row rather than something that may be unknown.
      "work" => Field.held(Repo.one(from e in Expression, where: e.id == ^id, select: e.work_id)),
      "manifestations" =>
        field(
          ids(from e in Embodiment, where: e.expression_id == ^id, select: e.manifestation_id),
          context,
          as: "manifestations"
        ),
      "aggregates" =>
        field(
          ids(
            from a in Aggregation,
              where: a.aggregating_expression_id == ^id,
              select: a.aggregated_expression_id
          ),
          context,
          as: "aggregates"
        ),
      "aggregated_by" =>
        field(
          ids(
            from a in Aggregation,
              where: a.aggregated_expression_id == ^id,
              select: a.aggregating_expression_id
          ),
          context,
          as: "aggregated_by"
        )
    }
  end

  defp related(%Res{kind: :manifestation, id: id}, context) do
    %{
      "expressions" =>
        field(
          ids(from e in Embodiment, where: e.manifestation_id == ^id, select: e.expression_id),
          context,
          as: "expressions"
        ),
      "items" =>
        field(ids(from i in Item, where: i.manifestation_id == ^id, select: i.id), context,
          as: "items"
        ),
      # spec-01 §5.2: zero digital items denotes a manifestation the household
      # describes but holds no file for, which is what establishes *not held*.
      "digital_items" =>
        field(
          ids(from d in DigitalItem, where: d.manifestation_id == ^id, select: d.id),
          context,
          as: "digital_items",
          otherwise: :not_held
        ),
      "parts" =>
        field(
          Repo.all(
            from p in ManifestationPart,
              where: p.whole_id == ^id,
              order_by: [asc_nulls_last: p.position, asc: p.part_id],
              select: %{"id" => p.part_id, "position" => p.position}
          ),
          context,
          as: "parts"
        ),
      "wholes" =>
        field(
          ids(from p in ManifestationPart, where: p.part_id == ^id, select: p.whole_id),
          context,
          as: "wholes"
        )
    }
  end

  defp related(%Res{kind: :item, id: id}, _context),
    do: %{
      "manifestation" =>
        Field.held(Repo.one(from i in Item, where: i.id == ^id, select: i.manifestation_id))
    }

  defp related(%Res{kind: :digital_item, id: id}, context) do
    %{
      "manifestation" =>
        Field.held(
          Repo.one(from d in DigitalItem, where: d.id == ^id, select: d.manifestation_id)
        ),
      # spec-01 §5.5: zero assets denotes a holding whose copies are all lost.
      "assets" =>
        field(ids(from a in Asset, where: a.digital_item_id == ^id, select: a.id), context,
          as: "assets",
          otherwise: :not_held
        )
    }
  end

  defp related(%Res{kind: :asset, id: id}, _context),
    do: %{
      "digital_item" =>
        Field.held(Repo.one(from a in Asset, where: a.id == ^id, select: a.digital_item_id))
    }

  # spec-01 §3.1's three agent kinds. An artist is an agent of an undetermined one of the
  # other two, which is what a credit read from a container names, so it answers for the
  # same relations: a surface that showed a person's work and not an artist's would show
  # nothing for almost every agent this deployment holds.
  defp related(%Res{kind: kind, id: id}, context)
       when kind in [:person, :collective_agent, :artist] do
    %{
      "created" =>
        field(ids(from c in WorkCreator, where: c.agent_id == ^id, select: c.work_id), context,
          as: "created"
        ),
      "credited_as" => field(credited_as(id), context, as: "credited_as")
    }
  end

  defp related(%Res{kind: :nomen, id: id}, _context),
    do: %{
      "names" => Field.held(Repo.one(from n in Nomen, where: n.id == ^id, select: n.res_id))
    }

  defp related(%Res{kind: :address, id: id}, _context),
    do: %{
      "target" => Field.held(Repo.one(from a in Address, where: a.id == ^id, select: a.target_id))
    }

  defp related(%Res{kind: :annotation, id: id}, _context),
    do: %{"target" => Field.held(Repo.get!(Annotation, id).target_id)}

  defp related(%Res{}, _context), do: %{}

  defp own(%Res{kind: :asset, id: id}, context) do
    asset = Repo.get!(Asset, id)

    roles =
      Repo.all(
        from r in AssetRole,
          where: r.asset_id == ^id,
          select: %{"class" => r.role_class, "role" => r.role}
      )

    # `location` is deliberately absent from the wire: spec-03 §10 asks that an
    # asset's location not be exposed on a reachable surface, and spec-10 §5.2
    # lets the deployment say which fields it carries.
    %{
      "size" => Field.held(asset.size),
      "digest" => Field.held(asset.digest),
      "digest_algorithm" => Field.held(asset.digest_algorithm),
      "format" => Field.held(asset.format),
      "essence" => Field.held(asset.essence),
      "roles" => field(roles, context, as: "roles"),
      "part_sequence" => field(asset.part_sequence, context, as: "part_sequence"),
      "verified_at" => field(asset.verified_at, context, as: "verified_at")
    }
  end

  defp own(%Res{kind: :address, id: id}, context) do
    address = Catalog.get_address(id)

    basis =
      for column <- Address.basis(address.selector_type), into: %{} do
        name = to_string(column)
        {name, field(Map.fetch!(address, column), context, as: name)}
      end

    Map.merge(basis, %{
      "selector_type" => Field.held(address.selector_type),
      "target_kind" => Field.held(address.target_kind),
      "provenance" => Field.held(address_provenance(address))
    })
  end

  defp own(%Res{kind: :annotation, id: id}, _context) do
    annotation = Repo.get!(Annotation, id)

    %{
      "body_type" => Field.held(annotation.body_type),
      "body" => Field.held(annotation.body),
      "provenance" => Field.held(annotation_provenance(annotation))
    }
  end

  defp own(%Res{kind: :nomen, id: id}, context) do
    nomen = Repo.get!(Nomen, id)

    %{
      "nomen_string" => Field.held(nomen.nomen_string),
      "provenance" => Field.held(nomen.provenance),
      "language" =>
        field(nomen.language, context, as: "language", otherwise: language_absence(nomen)),
      "script" => field(nomen.script, context, as: "script"),
      "scheme" => field(nomen.scheme, context, as: "scheme"),
      "context_of_use" => field(nomen.context_of_use, context, as: "context_of_use"),
      "assigner_id" => field(nomen.assigner_id, context, as: "assigner_id")
    }
  end

  defp own(%Res{kind: :work, id: id}, context) do
    credits =
      Enum.map(
        credits(id),
        &Map.take(&1, [:role, :position, :name, :musicbrainz_id, :agent_id, :provenance])
      )

    %{"credits" => field(credits, context, as: "credits")}
  end

  defp own(%Res{kind: :manifestation}, context) do
    # The registry names which of a kind's fields a deriving tool answers for, and
    # where in its body the measurement sits (spec-10 §20).
    for descriptor <- Pluteus.Representation.Registry.derived_fields(:manifestation), into: %{} do
      name = descriptor["name"]
      key = descriptor["derived"]["key"]

      {name, field(Map.get(context.measurements, key), context, as: name)}
    end
  end

  defp own(%Res{}, _context), do: %{}

  defp field(value, context, options) do
    Field.of(value, absent(context, options[:as], options[:otherwise] || :not_yet_examined))
  end

  # spec-01 §7.2 settles a null language rather than leaving it open: the name
  # belongs to no language in the relevant sense. So the absence is established
  # by the record, and a state saying nobody has looked would be false. Unknown
  # is the third value, carried beside the null. A person's own assertion about
  # the field outranks both, which `Absence.state/3` applies.
  defp language_absence(%Nomen{language_unknown: true}), do: :unknown
  defp language_absence(%Nomen{language_unknown: false}), do: :known_absent

  defp address_provenance(%Address{derivation_id: nil}), do: "authored"
  defp address_provenance(%Address{}), do: "derived"

  defp annotation_provenance(%Annotation{derivation_id: nil} = annotation),
    do: %{"authored_by" => annotation.principal_id}

  defp annotation_provenance(%Annotation{derivation_id: derivation_id}) do
    derivation = Derivation |> Repo.get!(derivation_id) |> Repo.preload(:tool_version)

    %{"tool" => derivation.tool_version.tool, "version" => derivation.tool_version.version}
  end

  defp credits(work_id),
    do: Repo.all(from c in Credit, where: c.work_id == ^work_id, order_by: [c.role, c.position])

  defp ids(query), do: Repo.all(query)

  # What a credit names, which since spec-04 §6.9 is a work or an expression: an author
  # is credited on the text and a narrator on the reading of it, and both are credits of
  # the same agent. Each is listed as the res the credit names rather than resolved to
  # one level, because which of the two it is, is the fact the credit records.
  defp credited_as(agent_id) do
    ids(
      from c in Credit,
        where: c.agent_id == ^agent_id,
        order_by: [asc: c.role, asc: c.position, asc: c.id],
        select: coalesce(c.work_id, c.expression_id)
    )
  end
end
