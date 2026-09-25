defmodule Pluteus.Events do
  @moduledoc """
  Reads and writes over what each principal has done.

  §11.2 scopes events to the principal and forbids exposing one principal's
  events to another through any aggregate, recommendation surface, or resumption
  list. That is a property of this module's shape rather than of its callers:
  every read here takes the principal whose events are being read as its first
  argument, and none returns events across principals.

  Adding a function that does not is the way §11.2 would be violated, so the
  exported set is asserted in the conformance suite.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Addressing
  alias Pluteus.Catalog.Extent
  alias Pluteus.Events.Continuity
  alias Pluteus.Events.Event
  alias Pluteus.Events.ResumePosition
  alias Pluteus.Events.Thresholds
  alias Pluteus.Ingest.Place
  alias Pluteus.Repo

  @doc """
  Records that something happened, and on which of the principal's devices
  where one did it (spec-07 §3.3).
  """
  @spec record(Ecto.UUID.t(), Ecto.UUID.t(), String.t(), DateTime.t(), Ecto.UUID.t() | nil) ::
          {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def record(principal_id, res_id, type, occurred_at \\ DateTime.utc_now(), device_id \\ nil) do
    %Event{}
    |> Event.changeset(%{
      principal_id: principal_id,
      res_id: res_id,
      device_id: device_id,
      type: type,
      occurred_at: occurred_at
    })
    |> Repo.insert()
  end

  @doc """
  One principal's events, most recent first.
  """
  @spec for_principal(Ecto.UUID.t()) :: [Event.t()]
  def for_principal(principal_id) do
    Repo.all(
      from e in Event,
        where: e.principal_id == ^principal_id,
        order_by: [desc: e.occurred_at]
    )
  end

  @doc """
  How many times one principal has played one res.

  §11.1 makes play count a count over events rather than a stored number.
  """
  @spec play_count(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) :: non_neg_integer()
  def play_count(principal_id, res_id, type) do
    Repo.aggregate(
      from(e in Event,
        where: e.principal_id == ^principal_id and e.res_id == ^res_id and e.type == ^type
      ),
      :count
    )
  end

  @doc """
  How many times one principal played each of many res, and when it last did,
  as a map keyed by res identifier. A res the principal never played is absent.
  """
  @spec plays(Ecto.UUID.t(), [Ecto.UUID.t()], String.t()) ::
          %{Ecto.UUID.t() => {non_neg_integer(), DateTime.t()}}
  def plays(principal_id, res_ids, type) do
    Map.new(
      Repo.all(
        from e in Event,
          where: e.principal_id == ^principal_id and e.res_id in ^res_ids and e.type == ^type,
          group_by: e.res_id,
          select: {e.res_id, {count(e.id), max(e.occurred_at)}}
      )
    )
  end

  @doc """
  Records how far through something a principal is, on one of its devices.

  Takes the session's own facts and nothing else: the device, the position and its
  unit, when it was reported, the session's sequence and whether it was playing.

  **The whole extent is read from the catalog, never from the report.** [spec-10]
  §13.2 measures its floor and ceiling against it, so a session that named its own
  extent could decide what counts as finished. spec-01 §8.4's recorded figure is
  the deployment's, and a res with none in the position's unit raises.

  A report is stored with the `reported_at` and `sequence` it was made with, so one
  flushed from an offline queue is weighed by §13.3 against its contemporaries.

  A position above the ceiling is not kept, and the res is recorded as consumed:
  spec-01 §11.3 makes *completed* something the deployment establishes rather than
  something a client reports, so that a surface and a count cannot disagree about
  what finishing means.
  """
  @spec report_position(map()) ::
          {:ok, ResumePosition.t()}
          | {:discarded, Thresholds.outcome()}
          | {:error, Ecto.Changeset.t()}
  def report_position(%{res_id: res_id, position: position, unit: unit} = report) do
    case Thresholds.weigh(category!(res_id), position, extent(res_id, unit)) do
      :keep -> put_position(report)
      :consumed -> consumed(report)
      outcome -> {:discarded, outcome}
    end
  end

  @doc """
  The position a surface shows for one res, of the several a principal's devices
  may hold ([spec-10] §13.3), or nil where every one of them is ignored.
  """
  @spec resume_position(Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) :: ResumePosition.t() | nil
  def resume_position(principal_id, res_id, now \\ DateTime.utc_now()) do
    principal_id |> positions_for(res_id) |> Continuity.winner(now)
  end

  @doc """
  Every position a principal's devices hold for one res.

  §13.3 keeps both where two sessions are playing one res at once, each attributed
  to its device, so a surface that needs to say where each of them is asks for all
  of them.
  """
  @spec positions_for(Ecto.UUID.t(), Ecto.UUID.t()) :: [ResumePosition.t()]
  def positions_for(principal_id, res_id) do
    Repo.all(
      from r in ResumePosition,
        where: r.principal_id == ^principal_id and r.res_id == ^res_id,
        order_by: [desc: r.reported_at, desc: r.sequence, asc: r.device_id]
    )
  end

  @doc """
  What one principal has left part-way through, one entry per res, most recently
  interacted with first ([spec-10] §13.4).

  Recency is a fact the person generated and can predict. Every other ordering is
  a judgement about what they should return to, computed from their behaviour.
  """
  @spec resumable(Ecto.UUID.t(), DateTime.t()) :: [ResumePosition.t()]
  def resumable(principal_id, now \\ DateTime.utc_now()) do
    Repo.all(
      from r in ResumePosition,
        where: r.principal_id == ^principal_id,
        order_by: [desc: r.reported_at]
    )
    |> Enum.group_by(& &1.res_id)
    |> Enum.map(fn {_res_id, positions} -> Continuity.winner(positions, now) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.reported_at, {:desc, DateTime})
  end

  defp put_position(report) do
    %ResumePosition{}
    |> ResumePosition.changeset(report)
    |> Repo.insert(
      on_conflict:
        {:replace, [:position, :unit, :reported_at, :sequence, :playing, :comment, :updated_at]},
      conflict_target: [:principal_id, :res_id, :device_id]
    )
  end

  defp consumed(report) do
    {:ok, _event} =
      record(
        report.principal_id,
        report.res_id,
        "completed",
        report.reported_at,
        report.device_id
      )

    {:discarded, :consumed}
  end

  # spec-01 §8.4's figure for the res, in the unit the session reported its
  # position in. A category that keeps no position never reaches this, so a
  # photograph needs no extent to be reported against.
  defp extent(res_id, unit) do
    case Addressing.get_extent(res_id, unit) do
      nil -> nil
      %Extent{magnitude: magnitude} -> magnitude
    end
  end

  # A res being played has a category, because placement writes one (spec-04 §6.3)
  # and §13.2's thresholds are per category. One without cannot be weighed, and a
  # threshold chosen for it would be a value the registry does not hold.
  defp category!(res_id) do
    with work_id when not is_nil(work_id) <- Catalog.work_of(res_id),
         category when not is_nil(category) <-
           Catalog.category_of(work_id, Place.category_scheme()) do
      category
    else
      nil ->
        raise ArgumentError,
              "res #{res_id} carries no category, so §13.2's thresholds cannot be read for it"
    end
  end
end
