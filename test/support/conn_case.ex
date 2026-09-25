defmodule PluteusWeb.ConnCase do
  @moduledoc """
  Case template for tests that exercise the HTTP layer.

  Supplies a built `Plug.Conn`, verified routes, and the same SQL sandbox
  isolation as `Pluteus.DataCase`, so a request test can assert against
  database state without leaking it into the next test.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint PluteusWeb.Endpoint

      use PluteusWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import PluteusWeb.ConnCase
    end
  end

  setup tags do
    {:ok, [conn: Phoenix.ConnTest.build_conn()] ++ Pluteus.DataCase.setup_sandbox(tags)}
  end

  @doc """
  A request as the authenticating proxy forwards it: carrying the proxy's
  secret and the identity the provider vouched for.
  """
  def through_proxy(conn, subject) do
    config = Application.fetch_env!(:pluteus, PluteusWeb.ForwardAuth)

    conn
    |> Plug.Conn.put_req_header(
      Keyword.fetch!(config, :secret_header),
      Keyword.fetch!(config, :secret)
    )
    |> Plug.Conn.put_req_header(Keyword.fetch!(config, :subject_header), subject)
  end

  @doc """
  A request as the proxy forwards it on the surface exempt from forward
  authentication: carrying the proxy's secret and no identity.
  """
  def via_proxy(conn) do
    config = Application.fetch_env!(:pluteus, PluteusWeb.ForwardAuth)

    Plug.Conn.put_req_header(
      conn,
      Keyword.fetch!(config, :secret_header),
      Keyword.fetch!(config, :secret)
    )
  end

  @doc """
  The issuer the proxy's identities come from, as configured.
  """
  def issuer,
    do: Keyword.fetch!(Application.fetch_env!(:pluteus, PluteusWeb.ForwardAuth), :issuer)

  @doc """
  An identity subject no other test will use.

  `principal_identities` is unique on `(issuer, subject)`, so two async tests binding one
  subject contend on that index: each holds its row uncommitted, and the second waits for
  the first to finish. The Repo's timeout outlasts a test's, so the slow holder passes
  and some unrelated test fails instead, wherever it happened to be waiting.

  A test asserting on a particular subject passes its own. Every other test takes one of
  these, so no two can collide however long either runs.
  """
  def a_subject(name \\ "ada"),
    do: "#{name}-#{System.unique_integer([:positive])}@household.test"
end
