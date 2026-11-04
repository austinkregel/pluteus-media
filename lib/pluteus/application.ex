defmodule Pluteus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Pluteus.Storage.Mount

  @impl true
  def start(_type, _args) do
    # Before anything opens a connection or serves a request. A node that came up
    # without its volumes would write the household's bytes onto whatever disk the
    # mount point sits on, and report every asset it could not read as unreadable.
    :ok = Mount.ensure!()

    children = [
      PluteusWeb.Telemetry,
      Pluteus.Repo,
      # Before Oban, which is the only thing that reads it.
      Pluteus.Jobs.Repo,
      # Before Oban too, whose stages fetch, import and read the corpora.
      Pluteus.Corpus.Repo,
      {DNSCluster, query: Application.get_env(:pluteus, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pluteus.PubSub},
      {Oban, Application.fetch_env!(:pluteus, Oban)},
      Pluteus.Changes.Consumption,
      release(),
      onboarding(),
      design_watcher(),
      # Start to serve requests, typically the last entry
      PluteusWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pluteus.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # A deployment with no principals writes a one-time onboarding secret to the
  # console once the database is reachable (spec-06 §6.5).
  defp onboarding do
    if Application.fetch_env!(:pluteus, :announce_onboarding),
      do: Supervisor.child_spec({Task, &Pluteus.Onboarding.announce/0}, restart: :temporary),
      else: Supervisor.child_spec({Task, fn -> :ok end}, restart: :temporary)
  end

  # Saving a design token rewrites the stylesheet, so a value is as cheap to try as
  # Annex A says it is. Development only: a release replaces `priv` rather than editing
  # it underneath a running node, and there is no `assets/` there to write to.
  defp design_watcher do
    if Keyword.fetch!(Application.fetch_env!(:pluteus, Pluteus.Design.Watcher), :start),
      do: Pluteus.Design.Watcher,
      else: Supervisor.child_spec({Task, fn -> :ok end}, restart: :temporary, id: :no_watcher)
  end

  # The feed's release reads the database on a timer, which a test's sandbox
  # does not permit from a process no test owns; tests start their own.
  defp release do
    if Keyword.fetch!(Application.fetch_env!(:pluteus, Pluteus.Changes.Release), :start),
      do: Pluteus.Changes.Release,
      else: Supervisor.child_spec({Task, fn -> :ok end}, restart: :temporary, id: :no_release)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PluteusWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
