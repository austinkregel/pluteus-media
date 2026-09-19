ExUnit.start(max_cases: 32)

# A deployment has exactly one System principal, and every sandboxed test that
# made its own would wait on that uniqueness for every other test holding one
# uncommitted. It is made once, committed, before any test runs.
case Pluteus.Repo.get_by(Pluteus.Principals.Principal, role: "system") do
  nil -> {:ok, _} = Pluteus.Principals.create_principal(%{role: "system"})
  _system -> :ok
end

Ecto.Adapters.SQL.Sandbox.mode(Pluteus.Repo, :manual)
