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
    Pluteus.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
