defmodule Pluteus.Representation do
  @moduledoc """
  What the native API says about a res (spec-07 §4.1): its identifier and kind,
  its preferred name under a resolution profile, every nomen it carries, the
  identifiers of what it is related to by each relationship, what its kind
  records of its own, and its lifecycle state.

  A representation names related res by identifier and never embeds one. A
  related res may be recycled or purged, and an embedded copy would carry its
  state stale; a client that needs it asks for it, and learns where it stands.
  """

  import Ecto.Query, only: [from: 2]

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
  alias Pluteus.Repo

  @doc """
  The representation of a live res.
  """
  @spec of(Res.t(), Profile.t()) :: map()
  def of(%Res{} = res, %Profile{} = profile) do
    nomens = Catalog.nomens_for(res.id)

    %{
      "id" => res.id,
      "kind" => res.kind,
      "state" => "live",
      "name" => name(nomens, profile),
      "nomens" => Enum.map(nomens, &nomen/1),
      "categories" => Enum.map(Catalog.categories_of(res.id), &category/1),
      "related" => related(res),
      "own" => own(res)
    }
  end

  defp name([], _profile), do: nil
  defp name(nomens, profile), do: Resolution.choose(nomens, profile).nomen_string

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

  defp related(%Res{kind: :work, id: id}) do
    %{
      "expressions" => ids(from e in Expression, where: e.work_id == ^id, select: e.id),
      "creators" => ids(from c in WorkCreator, where: c.work_id == ^id, select: c.agent_id),
      "parts" => ids(from p in WorkPart, where: p.whole_id == ^id, select: p.part_id),
      "wholes" => ids(from p in WorkPart, where: p.part_id == ^id, select: p.whole_id)
    }
  end

  defp related(%Res{kind: :expression, id: id}) do
    %{
      "work" => Repo.one(from e in Expression, where: e.id == ^id, select: e.work_id),
      "manifestations" =>
        ids(from e in Embodiment, where: e.expression_id == ^id, select: e.manifestation_id),
      "aggregates" =>
        ids(
          from a in Aggregation,
            where: a.aggregating_expression_id == ^id,
            select: a.aggregated_expression_id
        ),
      "aggregated_by" =>
        ids(
          from a in Aggregation,
            where: a.aggregated_expression_id == ^id,
            select: a.aggregating_expression_id
        )
    }
  end

  defp related(%Res{kind: :manifestation, id: id}) do
    %{
      "expressions" =>
        ids(from e in Embodiment, where: e.manifestation_id == ^id, select: e.expression_id),
      "items" => ids(from i in Item, where: i.manifestation_id == ^id, select: i.id),
      "digital_items" =>
        ids(from d in DigitalItem, where: d.manifestation_id == ^id, select: d.id),
      "parts" =>
        Repo.all(
          from p in ManifestationPart,
            where: p.whole_id == ^id,
            order_by: [asc_nulls_last: p.position, asc: p.part_id],
            select: %{"id" => p.part_id, "position" => p.position}
        ),
      "wholes" => ids(from p in ManifestationPart, where: p.part_id == ^id, select: p.whole_id)
    }
  end

  defp related(%Res{kind: :item, id: id}),
    do: %{
      "manifestation" => Repo.one(from i in Item, where: i.id == ^id, select: i.manifestation_id)
    }

  defp related(%Res{kind: :digital_item, id: id}) do
    %{
      "manifestation" =>
        Repo.one(from d in DigitalItem, where: d.id == ^id, select: d.manifestation_id),
      "assets" => ids(from a in Asset, where: a.digital_item_id == ^id, select: a.id)
    }
  end

  defp related(%Res{kind: :asset, id: id}),
    do: %{
      "digital_item" => Repo.one(from a in Asset, where: a.id == ^id, select: a.digital_item_id)
    }

  defp related(%Res{kind: kind, id: id}) when kind in [:person, :collective_agent] do
    %{
      "created" => ids(from c in WorkCreator, where: c.agent_id == ^id, select: c.work_id),
      "credited_as" => ids(from c in Credit, where: c.agent_id == ^id, select: c.work_id)
    }
  end

  defp related(%Res{kind: :nomen, id: id}),
    do: %{"names" => Repo.one(from n in Nomen, where: n.id == ^id, select: n.res_id)}

  defp related(%Res{kind: :address, id: id}),
    do: %{"target" => Repo.one(from a in Address, where: a.id == ^id, select: a.target_id)}

  defp related(%Res{kind: :annotation, id: id}) do
    annotation = Repo.get!(Annotation, id)
    %{"target" => annotation.target_id, "derivation" => annotation.derivation_id}
  end

  defp related(%Res{}), do: %{}

  defp own(%Res{kind: :asset, id: id}) do
    asset = Repo.get!(Asset, id)

    asset
    |> Map.take([
      :size,
      :digest,
      :digest_algorithm,
      :format,
      :essence,
      :part_sequence,
      :verified_at
    ])
    |> Map.put(
      :roles,
      Repo.all(
        from r in AssetRole,
          where: r.asset_id == ^id,
          select: %{class: r.role_class, role: r.role}
      )
    )
  end

  defp own(%Res{kind: :address, id: id}) do
    id
    |> Catalog.get_address()
    |> Map.from_struct()
    |> Map.drop([:__meta__, :target, :id, :target_id, :inserted_at, :updated_at])
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp own(%Res{kind: :annotation, id: id}) do
    annotation = Repo.get!(Annotation, id)

    provenance =
      case annotation.derivation_id do
        nil ->
          %{authored_by: annotation.principal_id}

        derivation_id ->
          derivation = Derivation |> Repo.get!(derivation_id) |> Repo.preload(:tool_version)
          %{tool: derivation.tool_version.tool, version: derivation.tool_version.version}
      end

    %{body_type: annotation.body_type, body: annotation.body, provenance: provenance}
  end

  defp own(%Res{kind: :work, id: id}),
    do: %{
      credits:
        Enum.map(
          credits(id),
          &Map.take(&1, [:role, :position, :name, :musicbrainz_id, :agent_id, :provenance])
        )
    }

  defp own(%Res{}), do: %{}

  defp credits(work_id),
    do: Repo.all(from c in Credit, where: c.work_id == ^work_id, order_by: [c.role, c.position])

  defp ids(query), do: Repo.all(query)
end
