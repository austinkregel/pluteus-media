defmodule Pluteus.Changes do
  @moduledoc """
  Change notification (spec-07 §5): the feed of catalog writes, and the
  subscriptions a socket relays.

  The feed is the write record spec-06 §6.2 already keeps. It is read only up
  to the number `Pluteus.Changes.Release` has released, never past a write
  that may still be followed by a lower-numbered one committing.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Repo

  @pubsub Pluteus.PubSub

  @type entry :: %{number: pos_integer(), operation: String.t(), res: [Ecto.UUID.t()]}

  @doc """
  The writes numbered after `after_number` and at most `through`, in order, at
  most `limit` of them.
  """
  @spec feed(non_neg_integer(), pos_integer(), non_neg_integer()) :: [entry()]
  def feed(after_number, limit, through) do
    Repo.all(
      from w in "catalog_writes",
        where: w.id > ^after_number and w.id <= ^through,
        order_by: w.id,
        limit: ^limit,
        select: %{
          number: w.id,
          operation: fragment("lower(?)", w.operation),
          res: type(w.res_ids, {:array, Ecto.UUID})
        }
    )
  end

  @doc """
  Runs `fun` with its catalog writes reaching no feed entry, and returns what it
  returns.

  A purge is the one write the feed does not carry (spec-01 §14.2, [spec-07]
  §5.1). Propagation announces that something changed and never that something is
  absent: the recycling that preceded the purge was the entry, and a client that
  missed it is answered 410 on its next request. Feeding the purge would mean
  retaining it for as long as any client might be away to save that client one
  request it was going to make regardless.

  Because no write is numbered, `Pluteus.Changes.Release` has nothing to release
  and the socket pushes nothing either.

  Attribution is unaffected: the trigger still refuses a write with no acting
  principal, and spec-06 §6.2's record of who purged is the tombstone's
  `purged_by`.

  This opens a transaction because the setting is local to one; made outside, it
  would last a single statement. It is cleared before the transaction closes, so a
  transaction enclosing this one is not left silenced — every production path
  reaches a purge inside one.
  """
  @spec unrecorded((-> result)) :: result when result: term()
  def unrecorded(fun) do
    {:ok, result} =
      Repo.transaction(fn ->
        set("purge")
        result = fun.()
        set("")
        result
      end)

    result
  end

  defp set(reason) do
    Repo.query!("SELECT set_config('pluteus.unrecorded', $1, true)", [reason])
    :ok
  end

  @doc """
  Subscribes the caller to `{:released, number}` whenever the feed advances.
  """
  @spec subscribe_released() :: :ok
  def subscribe_released, do: Phoenix.PubSub.subscribe(@pubsub, "released")

  @spec broadcast_released(pos_integer()) :: :ok
  def broadcast_released(number),
    do: Phoenix.PubSub.broadcast(@pubsub, "released", {:released, number})

  @doc """
  Subscribes the caller to `{:consumption_changed, what}` whenever one
  principal's own consumption data changes. Only that principal's socket may
  call this for it (spec-06 §6.3).
  """
  @spec subscribe_consumption(Ecto.UUID.t()) :: :ok
  def subscribe_consumption(principal_id),
    do: Phoenix.PubSub.subscribe(@pubsub, "consumption:" <> principal_id)

  @spec broadcast_consumption(Ecto.UUID.t(), String.t()) :: :ok
  def broadcast_consumption(principal_id, what),
    do:
      Phoenix.PubSub.broadcast(
        @pubsub,
        "consumption:" <> principal_id,
        {:consumption_changed, what}
      )
end
