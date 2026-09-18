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
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Pluteus.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    if tags[:no_actor], do: [], else: [actor: act_as_member()]
  end

  defp act_as_member do
    {:ok, member} = Pluteus.Principals.create_principal(%{role: "member"})
    :ok = Pluteus.Actor.set(member.id)
    member
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
