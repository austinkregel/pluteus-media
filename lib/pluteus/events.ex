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

  alias Pluteus.Events.Event
  alias Pluteus.Events.ResumePosition
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
  Sets how far through something a principal is.
  """
  @spec set_resume_position(Ecto.UUID.t(), Ecto.UUID.t(), non_neg_integer()) ::
          {:ok, ResumePosition.t()} | {:error, Ecto.Changeset.t()}
  def set_resume_position(principal_id, res_id, position_ms) do
    %ResumePosition{}
    |> ResumePosition.changeset(%{
      principal_id: principal_id,
      res_id: res_id,
      position_ms: position_ms
    })
    |> Repo.insert(
      on_conflict: {:replace, [:position_ms, :updated_at]},
      conflict_target: [:principal_id, :res_id]
    )
  end

  @spec resume_position(Ecto.UUID.t(), Ecto.UUID.t()) :: ResumePosition.t() | nil
  def resume_position(principal_id, res_id) do
    Repo.get_by(ResumePosition, principal_id: principal_id, res_id: res_id)
  end

  @doc """
  What one principal has left part-way through.
  """
  @spec resumable(Ecto.UUID.t()) :: [ResumePosition.t()]
  def resumable(principal_id) do
    Repo.all(
      from r in ResumePosition,
        where: r.principal_id == ^principal_id,
        order_by: [desc: r.updated_at]
    )
  end
end
