defmodule Pluteus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PluteusWeb.Telemetry,
      Pluteus.Repo,
      {DNSCluster, query: Application.get_env(:pluteus, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pluteus.PubSub},
      {Oban, Application.fetch_env!(:pluteus, Oban)},
      # Start to serve requests, typically the last entry
      PluteusWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pluteus.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PluteusWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
