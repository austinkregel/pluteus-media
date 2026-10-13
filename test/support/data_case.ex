defmodule Pluteus.DataCase do
  @moduledoc """
  Case template for tests that touch the database.

  Every test runs inside an SQL sandbox transaction that is rolled back on
  exit, so no test observes another's writes. `async: true` is safe here
  because PostgreSQL's sandbox isolates by connection ownership rather than by
  a shared global transaction.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Pluteus.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Pluteus.DataCase
    end
  end

  setup tags do
    {:ok, Pluteus.DataCase.setup_sandbox(tags)}
  end

  @doc """
  Checks out a sandboxed connection and, unless the test is tagged `:no_actor`,
  attributes its catalog writes to a member.

  spec-06 §6.2 has the database refuse any catalog write with no acting
  principal, so a test that writes to the catalog needs one. A test about
  attribution sets its own with `Pluteus.Actor.as/2`; one that needs no
  principals to exist at all, such as onboarding, is tagged `:no_actor`.
  """
  # Both databases, because a test that enqueues or drains a job writes to the queue's and
  # to the catalogue's, and a connection checked out of one says nothing about the other.
  def setup_sandbox(tags) do
    owners =
      for repo <- [Pluteus.Repo, Pluteus.Jobs.Repo],
          do: Sandbox.start_owner!(repo, shared: not tags[:async])

    on_exit(fn -> Enum.each(owners, &Sandbox.stop_owner/1) end)

    if tags[:no_actor], do: [], else: [actor: act_as_member()]
  end

  defp act_as_member do
    {:ok, member} = Pluteus.Principals.create_principal(%{role: "member"})
    :ok = Pluteus.Actor.set(member.id)
    member
  end

  @doc """
  Every query the repo ran while the given work was done, in the order it ran them.

  Two different things are asserted with this and neither can be seen in an outcome. A
  lock order is invisible until two transactions meet, and the cost of a surface is
  invisible until the catalog is large: a surface that issues a query per row behaves
  correctly on three holdings and falls over on thirty thousand, so what has to be
  asserted is that the number does not grow.

  Not usable from an async test. The repo's telemetry is process-wide, so a test running
  beside one that collected queries would put its own in the same stream.
  """
  @spec queries_during((-> any())) :: [String.t()]
  def queries_during(work) do
    handler = "queries-#{System.unique_integer([:positive])}"
    collector = self()

    :telemetry.attach(
      handler,
      [:pluteus, :repo, :query],
      fn _event, _measurements, metadata, pid -> send(pid, {handler, metadata.query}) end,
      collector
    )

    try do
      work.()
    after
      :telemetry.detach(handler)
    end

    drain(handler, [])
  end

  defp drain(handler, seen) do
    receive do
      {^handler, query} -> drain(handler, [query | seen])
    after
      0 -> Enum.reverse(seen)
    end
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
