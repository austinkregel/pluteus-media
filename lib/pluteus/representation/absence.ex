defmodule Pluteus.Representation.Absence do
  @moduledoc """
  What establishes the state of a field that holds no value (spec-10 §5.2).

  §5.2 gives each state its own source, and this reads them in order:

  1. **An authored assertion** — *sought, not found*, *known unknowable* or
     *known absent*, carried by an annotation whose subject is a named field
     (spec-02 §6.5). Only a person writes one.
  2. **A finding at the current tool version** — *attempted, failed*. A tool
     looked and could not, which is a record of what the deployment attempted
     (spec-04 §9).
  3. **Otherwise** the state the caller names: *not held* where the catalog
     itself establishes it — zero digital items (spec-01 §5.2), zero assets
     (spec-01 §5.5) — and *not yet examined* everywhere else.

  **An authored assertion outranks a finding**, which is the precedence spec-01
  §7.5 gives a person's correction over an automatic match. A tool failing does
  not unsay what someone established.

  The last three are never inferred from the catalog's silence: a deployment MUST
  NOT report *sought, not found* where nobody has looked.

  Evidence is gathered once per page in two queries, whatever the number of res.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Annotations.Annotation
  alias Pluteus.Annotations.ToolVersion
  alias Pluteus.Ingest.Finding
  alias Pluteus.Repo
  alias Pluteus.Representation.Registry

  defstruct asserted: %{}, failed: MapSet.new()

  @type t :: %__MODULE__{asserted: %{String.t() => atom()}, failed: MapSet.t(String.t())}

  @doc """
  The evidence for each of many res, keyed by identifier. Every identifier asked
  for is a key, and a res with no evidence carries an empty struct.
  """
  @spec for_res([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => t()}
  def for_res([]), do: %{}

  def for_res(res_ids) do
    asserted = asserted(res_ids)
    failed = failed(res_ids)

    Map.new(res_ids, fn res_id ->
      {res_id,
       %__MODULE__{
         asserted: Map.get(asserted, res_id, %{}),
         failed: Map.get(failed, res_id, MapSet.new())
       }}
    end)
  end

  @doc """
  The evidence for one res.
  """
  @spec for_one(Ecto.UUID.t()) :: t()
  def for_one(res_id), do: Map.fetch!(for_res([res_id]), res_id)

  @doc """
  The state a field with no value is in, given the evidence and the state the
  catalog establishes where nothing else does.
  """
  @spec state(t(), String.t(), atom()) :: atom()
  def state(%__MODULE__{} = evidence, field, otherwise) do
    cond do
      assertion = Map.get(evidence.asserted, field) -> assertion
      MapSet.member?(evidence.failed, field) -> :attempted_failed
      true -> otherwise
    end
  end

  # spec-02 §6.5's bodies. Ordered by identifier so that where a person has
  # asserted twice about one field the later assertion stands, the identifier
  # being time-ordered (spec-01 §4.1).
  defp asserted(res_ids) do
    Repo.all(
      from a in Annotation,
        where: a.target_id in ^res_ids,
        where: a.body_type == ^Annotation.absence(),
        where: not is_nil(a.principal_id),
        order_by: a.id,
        select: {a.target_id, a.body}
    )
    |> Enum.reduce(%{}, fn {res_id, body}, acc ->
      Map.update(
        acc,
        res_id,
        %{body["field"] => String.to_existing_atom(body["assertion"])},
        &Map.put(&1, body["field"], String.to_existing_atom(body["assertion"]))
      )
    end)
  end

  # An analysis finding names the input, the tool and the version. Only one at the
  # tool's current version establishes *attempted, failed*: a failure at a version
  # a newer build has superseded says nothing about what the newer one would do,
  # and spec-04 §9 makes the input due again when the version changes.
  defp failed(res_ids) do
    current_sequence =
      from t in ToolVersion,
        where: t.tool == parent_as(:tool_version).tool,
        select: max(t.sequence)

    Repo.all(
      from f in Finding,
        join: tv in ToolVersion,
        as: :tool_version,
        on: tv.id == f.tool_version_id,
        where: f.stage == :analyse,
        where: f.input_id in ^res_ids,
        where: is_nil(f.cleared_at),
        where: tv.sequence == subquery(current_sequence),
        select: {f.input_id, tv.tool, f.detail}
    )
    |> Enum.reduce(%{}, fn {res_id, tool, detail}, acc ->
      failed = failed_fields(tool, detail)

      Map.update(acc, res_id, failed, &MapSet.union(&1, failed))
    end)
  end

  # A finding naming the field it is about fails that field alone: a tool may
  # measure several things and leave one of them undefined, and the others are
  # answered. A finding naming none is a failure of the whole run, so every field
  # the tool answers for is in it.
  defp failed_fields(_tool, %{"field" => field}), do: MapSet.new([field])
  defp failed_fields(tool, _whole_run), do: fields_of(tool)

  defp fields_of(tool) do
    for field <- Registry.absence_fields(),
        derived = field["derived"],
        derived["tool"] == tool,
        into: MapSet.new() do
      field["name"]
    end
  end
end
