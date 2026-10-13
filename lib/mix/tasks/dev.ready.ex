defmodule Mix.Tasks.Dev.Ready do
  @shortdoc "Checks that the running server's own build and database are current"

  @moduledoc """
  Compiles the development build and reports any migration its database has not run.

  The suite cannot vouch for either. `mix test` compiles `MIX_ENV=test`, and the `test`
  alias migrates the test database, so a green gate says nothing about the build the
  server is actually serving from or the database it is actually reading. Both have
  failed while the suite passed:

  A module in `_build/dev` compiled against an older version of another one warns on
  the next incremental compile, and `warnings_as_errors` turns that warning into a
  failure. The server recompiles per request, so the failure is every page answering
  500 — with nothing in the suite able to see it, because the test build compiled
  cleanly from different artefacts.

  A migration that has not run against the development database makes every request
  answer 503, for the same reason: the gate migrated the other database.

  Nothing here writes. A pending migration is reported rather than run, because which
  database to change is not a gate's decision.
  """

  use Mix.Task

  alias Pluteus.Storage.Mount

  @requirements []

  @impl Mix.Task
  def run(_args) do
    if Mix.env() == :dev, do: here(), else: in_dev()
  end

  # The gate runs as `MIX_ENV=test`, and one invocation of mix has one environment, so
  # the development build is reached by asking for it rather than by switching under
  # ourselves. The child's own output is the report, and its status is this task's.
  defp in_dev do
    {_output, status} =
      System.cmd("mix", ["dev.ready"],
        env: [{"MIX_ENV", "dev"}],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status != 0, do: exit({:shutdown, status})
  end

  defp here do
    Mix.Task.run("compile", ["--warnings-as-errors"])
    Mix.Task.run("app.config")

    marked!()

    case pending() do
      [] ->
        Mix.shell().info("the development build and database are current")

      versions ->
        Mix.raise("""
        the development database has not run #{length(versions)} migration(s):

        #{Enum.map_join(versions, "\n", &"  #{&1}")}

        Every request answers 503 until it does. Run them with:

            docker compose exec app mix ecto.migrate
        """)
    end
  end

  # The node will not start under a root that does not carry its sentinel, which is the
  # same class of failure as a stale build: the suite passes and every request is
  # refused, because the server never came up. The development tree owns its roots
  # rather than mounting them, so the remedy is to say so.
  defp marked! do
    unmarked =
      for {name, root} <- Mount.roots(),
          not File.regular?(Path.join(root, Mount.sentinel())),
          do: "  #{name} at #{root}"

    if unmarked != [] do
      Mix.raise("""
      the development build will not start; #{length(unmarked)} root(s) carry no \
      #{Mount.sentinel()}:

      #{Enum.join(unmarked, "\n")}

      These are directories this tree owns rather than volumes it mounts. Mark them with:

          docker compose run --rm app mix pluteus.mount.mark
      """)
    end
  end

  # Every repo the deployment configures, not the catalogue's alone: a migration pending
  # against the queue's database stops the queue as surely as one pending against the
  # catalogue's stops a request, and a check that named one of them would say the
  # development tree was current while a stage was not running.
  defp pending do
    for repo <- Application.fetch_env!(:pluteus, :ecto_repos),
        version <- pending_for(repo),
        do: version
  end

  defp pending_for(repo) do
    {:ok, versions, _started} =
      Ecto.Migrator.with_repo(repo, fn started ->
        for {:down, version, name} <- Ecto.Migrator.migrations(started),
            do: "#{inspect(repo)} #{version}_#{name}"
      end)

    versions
  end
end
