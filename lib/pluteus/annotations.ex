defmodule Pluteus.Annotations do
  @moduledoc """
  What a person asserts about a region and what code computes about one
  (spec-02).

  The two are one structure with different provenance and sharply different
  durability. Authored annotations are not regenerable, are backed up, survive
  the purge of what they were about, and are never superseded. Derived ones are
  regenerable by construction, go with their target, and are superseded by a
  newer run of the same tool over the same input.

  Supersession is decided by derivation identity alone (spec-02 §5.2). A
  confidence score in a body is never consulted: scores are not comparable
  across tools, often not across versions of one, and rarely calibrated.
  Superseded annotations are kept and identifiable rather than deleted.

  Authored annotations are household-visible, as names are (spec-01 §7.3), so
  nothing here filters by who is asking.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Pluteus.Annotations.Annotation
  alias Pluteus.Annotations.Derivation
  alias Pluteus.Annotations.ToolVersion
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Res
  alias Pluteus.Lifecycle
  alias Pluteus.Repo

  @doc """
  Records one run of a tool over an input.

  Takes `:tool`, `:version`, `:input_id`, `:parameters` and `:derived_at`, and
  optionally `:agent_id` for whoever ran it. The tool version is recorded the
  first time it is seen, which fixes its place in the order supersession reads.
  """
  @spec record_derivation(map()) :: {:ok, Derivation.t()} | {:error, term()}
  def record_derivation(attrs) do
    Multi.new()
    |> Multi.run(:tool_version, fn repo, _changes ->
      tool_version(repo, attrs[:tool], attrs[:version])
    end)
    |> Multi.run(:agent_kind, fn repo, _changes -> agent_kind(repo, attrs[:agent_id]) end)
    |> Multi.insert(:derivation, fn %{tool_version: tool_version, agent_kind: agent_kind} ->
      attrs =
        attrs
        |> Map.drop([:tool, :version])
        |> Map.put(:tool_version_id, tool_version.id)
        |> put_agent_kind(agent_kind)

      Derivation.changeset(%Derivation{}, attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{derivation: derivation}} -> {:ok, derivation}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Records an address a derivation produced: a segment boundary, a detected
  scene, an OCR word position. Nothing authored may be anchored to one.
  """
  @spec derive_address(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def derive_address(derivation_id, target_id, selector) do
    Catalog.create_address(target_id, Map.put(selector, :derivation_id, derivation_id))
  end

  @doc """
  Records an annotation.

  Give `:principal_id` for an authored one, with `:agent_id` where the
  principal asserted on someone's behalf, or `:derivation_id` for a derived one.
  Never both, never neither.
  """
  @spec annotate(map()) :: {:ok, Annotation.t()} | {:error, term()}
  def annotate(attrs) do
    Multi.new()
    |> Multi.insert(:res, Res.changeset(%Res{}, %{kind: :annotation}))
    |> Multi.run(:agent_kind, fn repo, _changes -> agent_kind(repo, attrs[:agent_id]) end)
    |> Multi.insert(:annotation, fn %{res: res, agent_kind: agent_kind} ->
      attrs = attrs |> Map.put(:id, res.id) |> put_agent_kind(agent_kind)
      Annotation.changeset(%Annotation{}, attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{annotation: annotation}} -> {:ok, annotation}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  The run of a tool over an input that currently stands: the newest version,
  and of runs at that version the latest.
  """
  @spec current_derivation(String.t(), Ecto.UUID.t()) :: Derivation.t() | nil
  def current_derivation(tool, input_id) do
    Repo.one(
      from d in Derivation,
        join: t in assoc(d, :tool_version),
        where: t.tool == ^tool and d.input_id == ^input_id,
        order_by: [desc: t.sequence, desc: d.derived_at, desc: d.id],
        limit: 1
    )
  end

  @doc """
  Every annotation on a target that currently stands: every authored one, and
  each derived one whose derivation is still the current run of its tool over
  its input.
  """
  @spec current_on(Ecto.UUID.t()) :: [Annotation.t()]
  def current_on(target_id) do
    Repo.all(
      from a in Annotation,
        where: a.target_id == ^target_id,
        where: is_nil(a.derivation_id) or a.derivation_id in subquery(current_derivations())
    )
  end

  @doc """
  Every derived annotation on a target that a newer run has superseded. They
  are kept, so that a supersession can be reviewed before anything is deleted.
  """
  @spec superseded_on(Ecto.UUID.t()) :: [Annotation.t()]
  def superseded_on(target_id) do
    Repo.all(
      from a in Annotation,
        where: a.target_id == ^target_id,
        where: not is_nil(a.derivation_id),
        where: a.derivation_id not in subquery(current_derivations())
    )
  end

  @doc """
  Every annotation a tool produced at a version recorded before the given one:
  the set a re-derivation would redo.
  """
  @spec produced_before(String.t(), String.t()) :: [Annotation.t()]
  def produced_before(tool, version) do
    pivot = Repo.get_by!(ToolVersion, tool: tool, version: version)

    Repo.all(
      from a in Annotation,
        join: d in Derivation,
        on: d.id == a.derivation_id,
        join: t in ToolVersion,
        on: t.id == d.tool_version_id,
        where: t.tool == ^tool and t.sequence < ^pivot.sequence
    )
  end

  @doc """
  The regions the current run of a tool produced that contain the instant an
  authored address begins at.

  spec-02 §3.3 makes this a query rather than a stored reference, so that a
  re-segmentation moves the answer without ever moving what the person said.
  """
  @spec covering(Address.t(), String.t()) :: [Address.t()]
  def covering(%Address{selector_type: type} = authored, tool)
      when type in [:temporal, :spatiotemporal] do
    case current_derivation(tool, authored.target_id) do
      nil ->
        []

      %Derivation{id: derivation_id} ->
        Repo.all(
          from a in Address,
            where: a.derivation_id == ^derivation_id,
            where: a.target_id == ^authored.target_id,
            where: a.start_ms <= ^authored.start_ms and a.end_ms > ^authored.start_ms,
            order_by: a.start_ms
        )
    end
  end

  @doc """
  Assembles named measurements into a vector for distance computation.

  The layout — which names, in what order, over what range, at what weight — is
  the assembling component's and nobody else's (spec-02 §6.3). It is applied to
  the stored body, so changing it never reads the media again (§7). An array
  measurement contributes its elements in index order. A name the layout asks
  for and the body lacks raises: a missing measurement is meant to be visible.
  A measurement the layout does not ask for is ignored, so adding one to a body
  is an additive change.
  """
  @spec assemble(map(), [{String.t(), number(), number(), number()}]) :: [float()]
  def assemble(body, layout) do
    Enum.flat_map(layout, fn {name, low, high, weight} ->
      body
      |> Map.fetch!(name)
      |> List.wrap()
      |> Enum.map(&((&1 - low) / (high - low) * weight))
    end)
  end

  @doc """
  An annotation as it should be shown, including what it was about and where
  that stands now.

  A purged target is reported, not raised: an authored annotation outliving the
  thing it described is an orphan by design (spec-02 §8.1), and its target is
  named by identifier.
  """
  @spec present(Ecto.UUID.t()) :: map()
  def present(annotation_id) do
    annotation = Repo.get!(Annotation, annotation_id)

    %{
      id: annotation.id,
      body_type: annotation.body_type,
      body: annotation.body,
      provenance: provenance(annotation),
      target: describe_target(annotation.target_id)
    }
  end

  defp provenance(%Annotation{derivation_id: nil} = annotation) do
    %{authored_by: annotation.principal_id, on_behalf_of: annotation.agent_id}
  end

  defp provenance(%Annotation{derivation_id: derivation_id}) do
    derivation = Derivation |> Repo.get!(derivation_id) |> Repo.preload(:tool_version)

    %{
      tool: derivation.tool_version.tool,
      version: derivation.tool_version.version,
      parameters: derivation.parameters,
      derived_at: derivation.derived_at
    }
  end

  defp describe_target(target_id) do
    case Repo.get(Address, target_id) do
      %Address{} = address ->
        %{address: address_state(address), resource: describe_res(address.target_id)}

      nil ->
        %{resource: describe_res(target_id)}
    end
  end

  defp address_state(%Address{} = address) do
    address
    |> Map.from_struct()
    |> Map.drop([:__meta__, :target, :inserted_at, :updated_at])
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp describe_res(res_id) do
    case Lifecycle.state(res_id) do
      {:live, res} ->
        %{id: res.id, kind: res.kind, state: :live}

      {:recycled, res, recycling} ->
        %{id: res.id, kind: res.kind, state: :recycled, restorable_until: recycling.purge_after}

      {:purged, res, tombstone} ->
        %{id: res.id, kind: res.kind, state: :purged, purged_at: tombstone.purged_at}
    end
  end

  defp current_derivations do
    from d in Derivation,
      join: t in assoc(d, :tool_version),
      distinct: [t.tool, d.input_id],
      order_by: [desc: t.sequence, desc: d.derived_at, desc: d.id],
      select: d.id
  end

  # Validated before the lookup, so a missing version is refused as input
  # rather than reaching a query that cannot compare against nil.
  defp tool_version(repo, tool, version) do
    with %Ecto.Changeset{valid?: true} = changeset <-
           ToolVersion.changeset(%ToolVersion{}, %{tool: tool, version: version}),
         nil <- repo.get_by(ToolVersion, tool: tool, version: version) do
      repo.insert(changeset)
    else
      %Ecto.Changeset{} = invalid -> {:error, invalid}
      %ToolVersion{} = found -> {:ok, found}
    end
  end

  defp agent_kind(_repo, nil), do: {:ok, nil}

  defp agent_kind(repo, agent_id) do
    case repo.get(Res, agent_id) do
      nil -> {:error, :no_such_agent}
      %Res{kind: kind} -> {:ok, kind}
    end
  end

  defp put_agent_kind(attrs, nil), do: attrs
  defp put_agent_kind(attrs, kind), do: Map.put(attrs, :agent_kind, kind)
end
