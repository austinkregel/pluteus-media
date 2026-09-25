defmodule Pluteus.Catalog do
  @moduledoc """
  Reads and writes over the catalog's shared identifier space.

  Subtypes are stored as two rows: one in `res`, which owns the identifier, and
  one in the subtype's own table keyed on it. Both are written in a single
  transaction, so a subtype row without its res, or the reverse, is not a state
  the store can be left in.

  Several functions here write more rows than their name suggests. §6.2 holds
  that a work comes into existence with its first expression and an expression
  with its first manifestation, and the database enforces that at commit, so
  there is no call that creates a work alone.

  Structural prohibitions are enforced by database triggers rather than
  changesets. A violation therefore raises `Postgrex.Error` instead of returning
  an invalid changeset: these are conditions the model forbids outright, not
  input a caller can correct and resubmit.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Aggregation
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.AssetRole
  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.Category
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Item
  alias Pluteus.Catalog.Manifestation
  alias Pluteus.Catalog.ManifestationPart
  alias Pluteus.Catalog.Measurement
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Work
  alias Pluteus.Catalog.WorkCreator
  alias Pluteus.Catalog.WorkPart
  alias Pluteus.Formats
  alias Pluteus.Repo
  alias Pluteus.Storage

  @measured ~w(size digest digest_algorithm format)a

  @doc """
  Inserts a res.

  Supply `:id` to insert under a specific identifier, as seed loading requires
  (spec-01 §4.2). Omit it and a UUIDv7 is generated.

  This writes the res row alone. §6.1 requires every kind but nomen and address
  to carry a name at commit, so a caller using this outside a transaction that
  also writes one wants `create_named_res/2` instead.
  """
  @spec create_res(map()) :: {:ok, Res.t()} | {:error, Ecto.Changeset.t()}
  def create_res(attrs) do
    %Res{}
    |> Res.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Inserts a res together with the name it is known by.

  §6.1 requires the name, so the two are written in one transaction: a res of a
  named kind is never briefly nameless and never left that way.
  """
  @spec create_named_res(atom(), String.t() | map()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def create_named_res(kind, name) do
    Multi.new()
    |> Multi.insert(:res, Res.changeset(%Res{}, %{kind: kind}))
    |> name_step(:res, name)
    |> Repo.transaction()
  end

  @doc """
  Inserts a res, leaving an existing row with the same identifier untouched.

  Seed replacement uses this rather than a delete and re-insert: a seeded res
  may carry names the household attached to it, and removing the row would take
  them with it (§7.5).
  """
  @spec upsert_res(map()) :: {:ok, Res.t()} | {:error, Ecto.Changeset.t()}
  def upsert_res(attrs) do
    %Res{}
    |> Res.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :id)
  end

  @doc """
  Removes shipped names the current release no longer carries.

  Identifiers of names the release still ships are kept rather than deleted and
  reinserted. §7.5 permits a local row to link to a seeded one, so a seeded
  identifier that disappears and returns would break the link across an upgrade
  that changed nothing about it.
  """
  @spec delete_seeded_nomens_except([Ecto.UUID.t()]) :: non_neg_integer()
  def delete_seeded_nomens_except(keep_ids) do
    {count, _} =
      Repo.delete_all(from n in Nomen, where: n.provenance == :seeded and n.id not in ^keep_ids)

    count
  end

  @doc """
  Inserts a nomen, or refreshes one already carrying the same identifier.
  """
  @spec upsert_nomen(map()) :: {:ok, Nomen.t()} | {:error, Ecto.Changeset.t() | atom()}
  def upsert_nomen(attrs) do
    replaceable = ~w(
      res_id assigner_id provenance nomen_string scheme language script
      context_of_use reference_source intended_audience script_conversion
      assigner_kind updated_at
    )a

    Multi.new()
    |> Multi.run(:res, fn _repo, _changes ->
      upsert_res(%{kind: :nomen, id: attrs[:id]})
    end)
    |> Multi.run(:assigner_kind, fn repo, _changes -> assigner_kind(repo, attrs[:assigner_id]) end)
    |> Multi.insert(
      :nomen,
      fn %{res: res, assigner_kind: assigner_kind} ->
        Nomen.changeset(%Nomen{}, nomen_attrs(attrs, res.id, assigner_kind))
      end,
      on_conflict: {:replace, replaceable},
      conflict_target: :id
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{nomen: nomen}} -> {:ok, nomen}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Inserts a nomen together with the res row that owns its identifier.

  On failure what is returned is whatever the failing step produced: a changeset
  where the write was rejected, and an atom where a lookup the write depended on
  found nothing.
  """
  @spec create_nomen(map()) :: {:ok, Nomen.t()} | {:error, Ecto.Changeset.t() | atom()}
  def create_nomen(attrs) do
    Multi.new()
    |> Multi.insert(:res, Res.changeset(%Res{}, %{kind: :nomen, id: attrs[:id]}))
    |> Multi.run(:assigner_kind, fn repo, _changes -> assigner_kind(repo, attrs[:assigner_id]) end)
    |> Multi.insert(:nomen, fn %{res: res, assigner_kind: assigner_kind} ->
      Nomen.changeset(%Nomen{}, nomen_attrs(attrs, res.id, assigner_kind))
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{nomen: nomen}} -> {:ok, nomen}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Brings a work into existence along with its first expression and manifestation.

  All three are required at commit by §6.2, so they are written together, and
  §6.1 requires each to be named, so the name is given to all three. They are
  three separate nomens and diverge from that point on: retitling the expression
  leaves the work's title alone.
  """
  @spec create_work(String.t() | map()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def create_work(name) do
    Multi.new()
    |> insert_entity(:work, :work, Work, %{})
    |> name_step(:work, name)
    |> insert_entity(:expression, :expression, Expression, fn %{work: work} ->
      %{work_id: work.id}
    end)
    |> name_step(:expression, name)
    |> insert_entity(:manifestation, :manifestation, Manifestation, %{})
    |> name_step(:manifestation, name)
    |> embody_step()
    |> Repo.transaction()
  end

  @doc """
  Adds a further expression to an existing work, with its first manifestation.
  """
  @spec add_expression(Ecto.UUID.t(), String.t() | map()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def add_expression(work_id, name) do
    Multi.new()
    |> insert_entity(:expression, :expression, Expression, %{work_id: work_id})
    |> name_step(:expression, name)
    |> insert_entity(:manifestation, :manifestation, Manifestation, %{})
    |> name_step(:manifestation, name)
    |> embody_step()
    |> Repo.transaction()
  end

  @doc """
  Adds a further expression to an existing work, embodied in a manifestation
  that already exists: a dub carried by the container that also carries the
  original audio.
  """
  @spec add_expression_embodied_in(Ecto.UUID.t(), Ecto.UUID.t(), String.t() | map()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def add_expression_embodied_in(work_id, manifestation_id, name) do
    Multi.new()
    |> insert_entity(:expression, :expression, Expression, %{work_id: work_id})
    |> name_step(:expression, name)
    |> Multi.insert(:embodiment, fn %{expression: expression} ->
      Embodiment.changeset(%Embodiment{}, %{
        expression_id: expression.id,
        manifestation_id: manifestation_id
      })
    end)
    |> Repo.transaction()
  end

  @doc """
  Brings a work and its first expression into existence embodied in a
  manifestation that already exists: a commentary carried in a film's
  container (§5.3).
  """
  @spec create_work_embodied_in(Ecto.UUID.t(), String.t() | map()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def create_work_embodied_in(manifestation_id, name) do
    Multi.new()
    |> insert_entity(:work, :work, Work, %{})
    |> name_step(:work, name)
    |> insert_entity(:expression, :expression, Expression, fn %{work: work} ->
      %{work_id: work.id}
    end)
    |> name_step(:expression, name)
    |> Multi.insert(:embodiment, fn %{expression: expression} ->
      Embodiment.changeset(%Embodiment{}, %{
        expression_id: expression.id,
        manifestation_id: manifestation_id
      })
    end)
    |> Repo.transaction()
  end

  @doc """
  Adds a further manifestation embodying an existing expression.

  A second, better scan of an original is this: a new manifestation under the
  expression already catalogued, leaving the work untouched.
  """
  @spec add_manifestation(Ecto.UUID.t(), String.t() | map()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def add_manifestation(expression_id, name) do
    Multi.new()
    |> insert_entity(:manifestation, :manifestation, Manifestation, %{})
    |> name_step(:manifestation, name)
    |> Multi.insert(:embodiment, fn %{manifestation: manifestation} ->
      Embodiment.changeset(%Embodiment{}, %{
        expression_id: expression_id,
        manifestation_id: manifestation.id
      })
    end)
    |> Repo.transaction()
  end

  @spec embody(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Embodiment.t()} | {:error, Ecto.Changeset.t()}
  def embody(expression_id, manifestation_id) do
    %Embodiment{}
    |> Embodiment.changeset(%{expression_id: expression_id, manifestation_id: manifestation_id})
    |> Repo.insert()
  end

  @spec create_item(Ecto.UUID.t(), String.t() | map()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def create_item(manifestation_id, name) do
    Multi.new()
    |> insert_entity(:item, :item, Item, %{manifestation_id: manifestation_id})
    |> name_step(:item, name)
    |> Repo.transaction()
  end

  @doc """
  Records a file, or package of files, carrying a manifestation's content.

  No asset is created alongside it. A digital item with none is a holding whose
  copies are all lost, which §5.5 requires be representable.
  """
  @spec create_digital_item(Ecto.UUID.t(), String.t() | map()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def create_digital_item(manifestation_id, name) do
    Multi.new()
    |> insert_entity(:digital_item, :digital_item, DigitalItem, %{
      manifestation_id: manifestation_id
    })
    |> name_step(:digital_item, name)
    |> Repo.transaction()
  end

  @doc """
  Records one stored copy of a digital item.

  Adding a derived asset — a thumbnail, a waveform, a machine transcript — adds
  nothing at the catalog layer. It carries no manifestation content of its own,
  and §5.5 forbids modelling one as a digital item.

  The name is the one the bytes arrived under, which `location` does not record:
  a path says where a file is filed, not what it was called when it turned up,
  and normalization overwrites the second while changing the first.

  The bytes must already be at `location`. Size, digest and format are taken
  from them here and cannot be supplied: a digest a caller asserts is a claim,
  and spec-03 §5.1 records what was actually read.

  `:id` may be supplied where the identifier was minted before the asset
  existed, as an acquisition's is (spec-04 §4.2).

  `:measurement` may be supplied in place of reading the bytes here: a
  `Measurement` that `measure/1` took of the same location. A caller about to
  write in a transaction measures first, so the transaction is not held open
  for as long as a large file takes to read.
  """
  @spec create_asset(Ecto.UUID.t(), map(), String.t() | map()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def create_asset(digital_item_id, attrs, name) do
    case Map.keys(attrs) -- (Map.keys(attrs) -- @measured) do
      [] ->
        :ok

      supplied ->
        raise ArgumentError, "#{inspect(supplied)} are read from the bytes, not supplied"
    end

    {roles, attrs} = Map.pop(attrs, :roles, [])
    {measurement, attrs} = Map.pop(attrs, :measurement)

    case measurement_of(measurement, attrs.location) do
      {:ok, %Measurement{} = measured} ->
        attrs =
          Map.merge(attrs, %{
            size: measured.size,
            digest: measured.digest,
            digest_algorithm: measured.digest_algorithm,
            format: measured.format,
            digital_item_id: digital_item_id
          })

        Multi.new()
        |> insert_entity(:asset, :asset, Asset, attrs)
        |> name_step(:asset, name)
        |> role_steps(roles)
        |> Repo.transaction()

      {:error, reason} ->
        {:error, :bytes, reason, %{}}
    end
  end

  defp measurement_of(nil, location), do: measure(location)

  defp measurement_of(%Measurement{location: location} = measured, location), do: {:ok, measured}

  defp measurement_of(%Measurement{location: other}, location) do
    raise ArgumentError, "a measurement of #{inspect(other)} is not one of #{inspect(location)}"
  end

  @doc """
  Reads the size, digest and format of the bytes at a location.
  """
  @spec measure(String.t()) :: {:ok, Measurement.t()} | {:error, term()}
  def measure(location) do
    with {:ok, measured} <- Storage.measure(location),
         {:ok, format} <- Formats.identify(location) do
      {:ok, struct!(Measurement, Map.merge(measured, %{location: location, format: format}))}
    end
  end

  @doc """
  Records a res's value in a categorization scheme, under one provenance.
  """
  @spec categorize(Ecto.UUID.t(), String.t(), String.t(), atom()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def categorize(res_id, scheme, value, provenance) do
    %Category{}
    |> Category.changeset(%{res_id: res_id, scheme: scheme, value: value, provenance: provenance})
    |> Repo.insert()
  end

  @doc """
  Records a member's correction of a res's category in a scheme, or changes
  the correction already recorded. It sits beside any automatic category rather
  than replacing it, and outranks it (§7.5).
  """
  @spec correct_category(Ecto.UUID.t(), String.t(), String.t()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def correct_category(res_id, scheme, value) do
    %Category{}
    |> Category.changeset(%{res_id: res_id, scheme: scheme, value: value, provenance: :local})
    |> Repo.insert(
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: [:res_id, :scheme, :provenance],
      returning: true
    )
  end

  @doc """
  A res's category in a scheme: a member's correction over an automatic
  assignment over a seeded one (§7.5), or nil where it has none.
  """
  @spec category_of(Ecto.UUID.t(), String.t()) :: String.t() | nil
  def category_of(res_id, scheme) do
    from(c in Category, where: c.res_id == ^res_id and c.scheme == ^scheme)
    |> Repo.all()
    |> Enum.min_by(
      &Enum.find_index(Nomen.provenance_rank(), fn p -> p == &1.provenance end),
      fn ->
        nil
      end
    )
    |> case do
      nil -> nil
      %Category{value: value} -> value
    end
  end

  @spec categories_of(Ecto.UUID.t()) :: [Category.t()]
  def categories_of(res_id), do: Repo.all(from c in Category, where: c.res_id == ^res_id)

  @doc """
  The categories of each of many res, keyed by identifier.

  A page of res costs one query for them rather than one each, which is what
  [spec-10] §11.2 asks of everything a tile needs. A res carrying none is absent.
  """
  @spec categories_of_many([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => [Category.t()]}
  def categories_of_many([]), do: %{}

  def categories_of_many(res_ids) do
    Repo.all(from c in Category, where: c.res_id in ^res_ids, order_by: [c.res_id, c.scheme])
    |> Enum.group_by(& &1.res_id)
  end

  @doc """
  The work a res belongs to, or nil where it belongs to none.

  A category is recorded on the work ([spec-04] §6.3), so a question about what
  kind of thing a manifestation is is a question about its work. A work is its
  own; an expression names one (§6.1); a manifestation, an item and a digital item
  reach one through what they embody or carry; a reified address reaches one
  through its target.

  A manifestation embodying expressions of several works (§5.3) answers with the
  first by identifier, so the answer is the same on every call.
  """
  @spec work_of(Ecto.UUID.t()) :: Ecto.UUID.t() | nil
  def work_of(res_id) do
    case Repo.get(Res, res_id) do
      nil -> nil
      %Res{kind: kind} -> work_of(kind, res_id)
    end
  end

  defp work_of(:work, id), do: id

  defp work_of(:expression, id),
    do: Repo.one(from e in Expression, where: e.id == ^id, select: e.work_id)

  defp work_of(:manifestation, id) do
    Repo.one(
      from e in Embodiment,
        join: x in Expression,
        on: x.id == e.expression_id,
        where: e.manifestation_id == ^id,
        order_by: x.work_id,
        limit: 1,
        select: x.work_id
    )
  end

  defp work_of(:digital_item, id) do
    from(d in DigitalItem, where: d.id == ^id, select: d.manifestation_id)
    |> Repo.one()
    |> through(:manifestation)
  end

  defp work_of(:item, id) do
    from(i in Item, where: i.id == ^id, select: i.manifestation_id)
    |> Repo.one()
    |> through(:manifestation)
  end

  defp work_of(:address, id) do
    case Repo.one(from a in Address, where: a.id == ^id, select: a.target_id) do
      nil -> nil
      target_id -> work_of(target_id)
    end
  end

  # None of these is a rendering of anything, so none belongs to a work. A kind
  # added to the model reaches no clause here and raises, which is the question
  # being asked rather than answered by default.
  defp work_of(kind, _id)
       when kind in [
              :res,
              :asset,
              :person,
              :collective_agent,
              :artist,
              :nomen,
              :place,
              :time_span,
              :annotation
            ],
       do: nil

  defp through(nil, _kind), do: nil
  defp through(id, kind), do: work_of(kind, id)

  @doc """
  Every asset holding a copy of the given digital item.
  """
  @spec assets_of(Ecto.UUID.t()) :: [Asset.t()]
  def assets_of(digital_item_id) do
    Repo.all(from a in Asset, where: a.digital_item_id == ^digital_item_id)
  end

  @doc """
  Narrows an artist to the kind of agent it turns out to be (spec-01 §3.1).

  The identifier is kept, and with it everything recorded against the artist:
  its names, the works it is credited with, and every principal's stars and
  ratings. This is the one change of kind the model permits. Anything else —
  narrowing a res that is not an artist, or narrowing to a kind that is not a
  person or a collective agent — is refused.
  """
  @spec narrow(Ecto.UUID.t(), :person | :collective_agent) ::
          {:ok, Res.t()} | {:error, :no_such_res | :not_an_artist | :not_an_agent_kind}
  def narrow(artist_id, kind) when kind in [:person, :collective_agent] do
    case Repo.get(Res, artist_id) do
      nil -> {:error, :no_such_res}
      %Res{kind: :artist} = artist -> artist |> Res.changeset(%{kind: kind}) |> Repo.update()
      %Res{} -> {:error, :not_an_artist}
    end
  end

  def narrow(_artist_id, _kind), do: {:error, :not_an_agent_kind}

  @doc """
  Credits an agent as a creator of a work (LRM-R5). The agent is a person, a
  collective agent or an artist; whether it holds a login does not enter into
  it.
  """
  @spec credit_creator(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, WorkCreator.t()} | {:error, term()}
  def credit_creator(work_id, agent_id) do
    case Repo.get(Res, agent_id) do
      nil ->
        {:error, :no_such_agent}

      %Res{kind: kind} ->
        %WorkCreator{}
        |> WorkCreator.changeset(%{work_id: work_id, agent_id: agent_id, agent_kind: kind})
        |> Repo.insert()
    end
  end

  @spec creators_of(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def creators_of(work_id) do
    Repo.all(from c in WorkCreator, where: c.work_id == ^work_id, select: c.agent_id)
  end

  @doc """
  Records an association between two res, refined by type (LRM-R1).

  §7.5's link between a household row and a seed for the same concept is one of
  these, written with `Association.same_thing/0`.
  """
  @spec associate(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) ::
          {:ok, Association.t()} | {:error, Ecto.Changeset.t()}
  def associate(subject_id, object_id, refinement) do
    %Association{}
    |> Association.changeset(%{
      subject_id: subject_id,
      object_id: object_id,
      refinement: refinement
    })
    |> Repo.insert()
  end

  @doc """
  Every res associated with the given one under a refinement, in either
  direction.
  """
  @spec associated(Ecto.UUID.t(), String.t()) :: [Ecto.UUID.t()]
  def associated(res_id, refinement) do
    Repo.all(
      from a in Association,
        where: a.refinement == ^refinement,
        where: a.subject_id == ^res_id or a.object_id == ^res_id,
        select: {a.subject_id, a.object_id}
    )
    |> Enum.map(fn {subject_id, object_id} ->
      if subject_id == res_id, do: object_id, else: subject_id
    end)
  end

  @doc """
  Reifies an address: a region within a res, given an identifier of its own.

  The target's kind is read from the res rather than supplied, so a caller
  cannot state one the row disagrees with. A selector invalid at the target's
  level (§8.5) fails the changeset before it reaches the database.
  """
  @spec create_address(Ecto.UUID.t(), map()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def create_address(target_id, selector) do
    Multi.new()
    |> Multi.run(:target, fn repo, _changes ->
      case repo.get(Res, target_id) do
        nil -> {:error, :no_such_res}
        %Res{} = target -> {:ok, target}
      end
    end)
    |> insert_entity(:address, :address, Address, fn %{target: target} ->
      Map.merge(selector, %{target_id: target.id, target_kind: target.kind})
    end)
    |> Repo.transaction()
  end

  @spec get_address(Ecto.UUID.t()) :: Address.t() | nil
  def get_address(id), do: Repo.get(Address, id)

  @doc """
  Every address reified against the given res.
  """
  @spec addresses_of(Ecto.UUID.t()) :: [Address.t()]
  def addresses_of(target_id) do
    Repo.all(from a in Address, where: a.target_id == ^target_id)
  end

  @doc """
  Places an aggregated expression at a position within its aggregate (§12.1).
  """
  @spec arrange(Ecto.UUID.t(), Ecto.UUID.t(), pos_integer()) :: non_neg_integer()
  def arrange(aggregating_expression_id, aggregated_expression_id, position) do
    {count, _} =
      Repo.update_all(
        from(a in Aggregation,
          where:
            a.aggregating_expression_id == ^aggregating_expression_id and
              a.aggregated_expression_id == ^aggregated_expression_id
        ),
        set: [arrangement: position]
      )

    count
  end

  @doc """
  The arrangement recorded for an aggregated expression, if any.
  """
  @spec arrangement_of(Ecto.UUID.t(), Ecto.UUID.t()) :: integer() | nil
  def arrangement_of(aggregating_expression_id, aggregated_expression_id) do
    Repo.one(
      from a in Aggregation,
        where:
          a.aggregating_expression_id == ^aggregating_expression_id and
            a.aggregated_expression_id == ^aggregated_expression_id,
        select: a.arrangement
    )
  end

  @doc """
  Records that one work's content is a component of another's (LRM-R18).

  Raises when the two works stand in an aggregating relationship, which §5.3
  forbids from being expressed as whole-part.
  """
  @spec add_work_part(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, WorkPart.t()} | {:error, Ecto.Changeset.t()}
  def add_work_part(whole_id, part_id) do
    %WorkPart{}
    |> WorkPart.changeset(%{whole_id: whole_id, part_id: part_id})
    |> Repo.insert()
  end

  @doc """
  Records that one manifestation is a component of another (LRM-R26), at a
  position within it where the whole is ordered.

  A position already taken in the whole is refused at commit.
  """
  @spec add_manifestation_part(Ecto.UUID.t(), Ecto.UUID.t(), pos_integer() | nil) ::
          {:ok, ManifestationPart.t()} | {:error, Ecto.Changeset.t()}
  def add_manifestation_part(whole_id, part_id, position) do
    %ManifestationPart{}
    |> ManifestationPart.changeset(%{whole_id: whole_id, part_id: part_id, position: position})
    |> Repo.insert()
  end

  @doc """
  The parts of a manifestation, in position order.
  """
  @spec parts_of(Ecto.UUID.t()) :: [ManifestationPart.t()]
  def parts_of(whole_id) do
    Repo.all(
      from p in ManifestationPart,
        where: p.whole_id == ^whole_id,
        order_by: [asc_nulls_last: p.position, asc: p.part_id]
    )
  end

  @doc """
  The manifestations a manifestation is a part of.
  """
  @spec wholes_of(Ecto.UUID.t()) :: [ManifestationPart.t()]
  def wholes_of(part_id) do
    Repo.all(from p in ManifestationPart, where: p.part_id == ^part_id)
  end

  @doc """
  Records that one expression selects another as part of its plan (LRM-R25).

  Raises when the works behind them already stand in a whole-part relation.
  """
  @spec aggregate(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Aggregation.t()} | {:error, Ecto.Changeset.t()}
  def aggregate(aggregating_expression_id, aggregated_expression_id) do
    %Aggregation{}
    |> Aggregation.changeset(%{
      aggregating_expression_id: aggregating_expression_id,
      aggregated_expression_id: aggregated_expression_id
    })
    |> Repo.insert()
  end

  @spec get_res(Ecto.UUID.t()) :: Res.t() | nil
  def get_res(id), do: Repo.get(Res, id)

  @spec get_nomen(Ecto.UUID.t()) :: Nomen.t() | nil
  def get_nomen(id), do: Repo.get(Nomen, id)

  @doc """
  Every nomen naming the given res.
  """
  @spec nomens_for(Ecto.UUID.t()) :: [Nomen.t()]
  def nomens_for(res_id) do
    Repo.all(from n in Nomen, where: n.res_id == ^res_id)
  end

  @doc """
  Every nomen carrying the given scheme and string.

  Returns a list because §4.3 permits the same external identifier to appear on
  more than one entity.
  """
  @spec nomens_by_external_identifier(String.t(), String.t()) :: [Nomen.t()]
  def nomens_by_external_identifier(scheme, nomen_string) do
    Repo.all(
      from n in Nomen,
        where: n.scheme == ^scheme and n.nomen_string == ^nomen_string
    )
  end

  @doc """
  The work each of many res belongs to, keyed by identifier.

  The batched form of `work_of/1`, for the kinds a surface draws: a work is its own, an
  expression names one, and a manifestation, an item or a digital item reaches one
  through what it embodies or carries. A kind that belongs to no work is absent rather
  than present with a nil, and nothing here walks a reified address, which `work_of/1`
  does one at a time.
  """
  @spec works_of_many([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => Ecto.UUID.t()}
  def works_of_many([]), do: %{}

  def works_of_many(res_ids) do
    direct = Map.new(Repo.all(from w in Work, where: w.id in ^res_ids, select: {w.id, w.id}))

    from_expressions =
      Map.new(Repo.all(from e in Expression, where: e.id in ^res_ids, select: {e.id, e.work_id}))

    Enum.reduce(
      [direct, from_expressions, through_manifestations(res_ids), through_carriers(res_ids)],
      %{},
      &Map.merge(&2, &1)
    )
  end

  # A manifestation embodying expressions of several works answers with the first by
  # identifier, so the answer is the same on every call, as `work_of/1` does.
  defp through_manifestations(res_ids) do
    Map.new(
      Repo.all(
        from e in Embodiment,
          join: x in Expression,
          on: x.id == e.expression_id,
          where: e.manifestation_id in ^res_ids,
          order_by: [desc: x.work_id],
          select: {e.manifestation_id, x.work_id}
      )
    )
  end

  defp through_carriers(res_ids) do
    Map.new(
      Repo.all(
        from d in DigitalItem,
          join: e in Embodiment,
          on: e.manifestation_id == d.manifestation_id,
          join: x in Expression,
          on: x.id == e.expression_id,
          where: d.id in ^res_ids,
          order_by: [desc: x.work_id],
          select: {d.id, x.work_id}
      )
    )
  end

  @doc """
  Moves an expression under another work, which is LRM-R2 restated for an
  expression already recorded.

  `embody/2` adds an embodiment because LRM-R3 is many to many; LRM-R2 is 1 to M
  and lives in a column, so realizing an expression under another work replaces
  the one it had rather than adding to it. That asymmetry is the relations', not a
  choice made here.

  This is how spec-03 §8.3's *same work* decision is carried out: two expressions
  that turn out to realize one creation are brought under one work, and neither is
  merged into the other.
  """
  @spec realize(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Expression.t()} | {:error, Ecto.Changeset.t()}
  def realize(work_id, expression_id) do
    Expression
    |> Repo.get!(expression_id)
    |> Expression.changeset(%{work_id: work_id})
    |> Repo.update()
  end

  @doc """
  Every expression realizing the given work.
  """
  @spec expressions_of(Ecto.UUID.t()) :: [Expression.t()]
  def expressions_of(work_id) do
    Repo.all(from e in Expression, where: e.work_id == ^work_id)
  end

  @doc """
  Every manifestation embodying the given expression.
  """
  @spec manifestations_of(Ecto.UUID.t()) :: [Manifestation.t()]
  def manifestations_of(expression_id) do
    Repo.all(
      from m in Manifestation,
        join: e in Embodiment,
        on: e.manifestation_id == m.id,
        where: e.expression_id == ^expression_id
    )
  end

  @doc """
  Every expression embodied in the given manifestation.
  """
  @spec expressions_in(Ecto.UUID.t()) :: [Expression.t()]
  def expressions_in(manifestation_id) do
    Repo.all(
      from x in Expression,
        join: e in Embodiment,
        on: e.expression_id == x.id,
        where: e.manifestation_id == ^manifestation_id
    )
  end

  # LRM-R14's range is agent, and the database enforces it through the pair of
  # columns. The caller states the assigner; which kind of res that is, the res
  # already knows.
  defp assigner_kind(_repo, nil), do: {:ok, nil}

  defp assigner_kind(repo, assigner_id) do
    case repo.get(Res, assigner_id) do
      nil -> {:error, :no_such_assigner}
      %Res{kind: kind} -> {:ok, kind}
    end
  end

  defp nomen_attrs(attrs, id, nil), do: Map.put(attrs, :id, id)

  defp nomen_attrs(attrs, id, assigner_kind) do
    attrs |> Map.put(:id, id) |> Map.put(:assigner_kind, assigner_kind)
  end

  # §5.5 requires every asset to carry at least one role, and permits several
  # where they coincide on one byte sequence.
  defp role_steps(multi, roles) do
    roles
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {role, index}, acc ->
      Multi.insert(acc, {:asset_role, index}, fn %{asset: asset} ->
        AssetRole.changeset(%AssetRole{}, Map.put(role, :asset_id, asset.id))
      end)
    end)
  end

  # A name given to a constructor is a household name: §7.3 makes the null
  # assigner the unmarked case, and a name belonging to one person is added
  # afterwards with `create_nomen/1`, which can look its assigner's kind up.
  defp name_step(multi, entity, name) do
    insert_entity(multi, :"#{entity}_nomen", :nomen, Nomen, fn changes ->
      name
      |> nomen_attrs()
      |> Map.put(:res_id, Map.fetch!(changes, entity).id)
    end)
  end

  defp nomen_attrs(name) when is_binary(name), do: %{nomen_string: name}
  defp nomen_attrs(attrs) when is_map(attrs), do: attrs

  defp embody_step(multi) do
    Multi.insert(multi, :embodiment, fn %{expression: expression, manifestation: manifestation} ->
      Embodiment.changeset(%Embodiment{}, %{
        expression_id: expression.id,
        manifestation_id: manifestation.id
      })
    end)
  end

  defp insert_entity(multi, name, kind, schema, attrs) do
    res_key = :"#{name}_res"
    id = if is_map(attrs), do: Map.get(attrs, :id)

    multi
    |> Multi.insert(res_key, Res.changeset(%Res{}, %{kind: kind, id: id}))
    |> Multi.insert(name, fn changes ->
      base = if is_function(attrs, 1), do: attrs.(changes), else: attrs
      id = Map.fetch!(changes, res_key).id

      schema.changeset(struct(schema), Map.put(base, :id, id))
    end)
  end
end
