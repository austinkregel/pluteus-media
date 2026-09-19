defmodule Pluteus.Actor do
  @moduledoc """
  The principal a transaction's catalog writes are attributed to.

  spec-06 §6.2 requires every catalog write to record the acting principal. The
  database enforces it: each catalog table's trigger reads `pluteus.actor` for
  the current transaction and refuses a write when it is unset or names a
  principal that does not exist. Code therefore cannot forget to attribute a
  write; it can only fail to make one.
  """

  alias Pluteus.Repo

  @doc """
  Runs `fun` with its catalog writes attributed to `principal_id`, and returns
  what it returns.

  The previous actor is restored afterwards, so a nested call attributes only
  the writes inside it.

  Where `fun` returns `{:error, reason}`, the transaction is rolled back and the
  error returned. A write that failed inside it has already doomed the
  transaction, and nothing further may be run in it, restoring the actor
  included; the actor is local to the transaction, and goes with it.
  """
  @spec as(Ecto.UUID.t(), (-> result)) :: result | {:error, term()} when result: term()
  def as(principal_id, fun) do
    case Repo.transaction(fn ->
           previous = current()
           set(principal_id)
           conclude(fun.(), previous)
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp conclude({:error, reason}, _previous), do: Repo.rollback(reason)

  defp conclude(result, previous) do
    set(previous || "")
    result
  end

  @doc """
  Attributes the rest of the current transaction's catalog writes to
  `principal_id`. Outside a transaction it lasts for one statement, which is
  never what a caller wants; `as/2` is the ordinary entry point.
  """
  @spec set(Ecto.UUID.t() | String.t()) :: :ok
  def set(principal_id) do
    Repo.query!("SELECT set_config('pluteus.actor', $1, true)", [principal_id])
    :ok
  end

  @spec current() :: String.t() | nil
  def current do
    case Repo.query!("SELECT current_setting('pluteus.actor', true)").rows do
      [[value]] when value in [nil, ""] -> nil
      [[value]] -> value
    end
  end
end
