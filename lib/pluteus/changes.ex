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
