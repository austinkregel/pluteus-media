defmodule Pluteus.PlatformEvents do
  @moduledoc """
  Reads and writes over what happened to the holdings: spec-01 §11.2's platform
  class.

  The counterpart of `Pluteus.Events`, and deliberately its opposite in shape.
  Every read there takes the principal whose events are being read as its first
  argument, because §11.2 scopes a consumption event to one principal. **No read
  here takes a principal at all**, because §11.2 makes a platform event visible to
  the household and spec-06 §6.4 names them among the three things a member
  contributes that the household sees by design.

  So the two classes are two modules over two tables, and which class a type
  belongs to is which table records it. That is what makes §11.2's "Every event is
  exactly one of" true by construction rather than by a column nobody may get
  wrong, and it is what makes criterion 42 — no platform event carries, or can be
  combined into, what any principal consumed — a property of the schema.

  `Pluteus.Administration.audit_trail/0` is the other unscoped household-wide
  reader, and this follows it.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Events.PlatformEvent
  alias Pluteus.Repo

  @doc """
  Records that something happened to the holdings, and which principal did it.

  `recorded_by` is the acting principal, usually the System principal's own
  processes (spec-04 §3). It does not decide the class (§11.2) and does not scope
  the read.
  """
  @spec record(String.t(), Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, PlatformEvent.t()} | {:error, Ecto.Changeset.t()}
  def record(type, res_id, recorded_by, occurred_at \\ DateTime.utc_now()) do
    %PlatformEvent{}
    |> PlatformEvent.changeset(%{
      type: type,
      res_id: res_id,
      recorded_by: recorded_by,
      occurred_at: occurred_at
    })
    |> Repo.insert()
  end

  @doc """
  Every platform event, most recent first, at most `limit` of them.

  No principal argument, by design: the household sees all of them, including the
  ones the System principal recorded.
  """
  @spec all(pos_integer()) :: [PlatformEvent.t()]
  def all(limit \\ 100) do
    Repo.all(from e in PlatformEvent, order_by: [desc: e.occurred_at, desc: e.id], limit: ^limit)
  end

  @doc """
  Every platform event about one res, most recent first.
  """
  @spec about(Ecto.UUID.t()) :: [PlatformEvent.t()]
  def about(res_id) do
    Repo.all(
      from e in PlatformEvent,
        where: e.res_id == ^res_id,
        order_by: [desc: e.occurred_at, desc: e.id]
    )
  end
end
