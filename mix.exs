defmodule Pluteus.MixProject do
  use Mix.Project

  def project do
    [
      app: :pluteus,
      version: "0.1.0",
      elixir: ">= 1.19.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Pluteus.Application, []},
      extra_applications: [:logger, :runtime_tools, :inets, :ssl, :xmerl]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.5"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:file_system, "~> 1.1"},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:uuidv7, "~> 1.0"},
      {:oban, "~> 2.24"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_json_schema, "~> 0.11", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      # `design.build` runs ahead of `tailwind` because the stylesheet it writes is
      # what Tailwind's input imports (spec-10 Annex A.10).
      "assets.build": ["compile", "design.build", "tailwind pluteus", "esbuild pluteus"],
      "assets.deploy": [
        "design.build",
        "tailwind pluteus --minify",
        "esbuild pluteus --minify",
        "phx.digest"
      ],
      # `dev.ready` sits beside the test build's own compile because the two fail
      # independently: a green suite says nothing about the build the server serves
      # from, nor about whether its database has run the migrations in this tree.
      precommit: [
        "compile --warnings-as-errors",
        "dev.ready",
        "deps.unlock --unused",
        "format --check-formatted",
        "credo --strict",
        "test"
      ]
    ]
  end
end
