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
    Pluteus.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Pluteus.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
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
