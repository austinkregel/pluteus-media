defmodule Pluteus.Proxy do
  @moduledoc """
  The authenticating proxy, for a browser driven by a test.

  Pluteus runs no login flow. It reads the identity a reverse proxy has established and
  reads it only from a request that also carries a secret the proxy injects and a browser
  cannot — so a surface is unreachable without something in front of it doing that job.
  `nginx/dev.conf` is that something in development, and this is it for a test.

  **It is not an authentication bypass, and there is none.** It asserts an identity the
  way the development proxy does, by setting the two headers `PluteusWeb.ForwardAuth`
  reads, and the application is unchanged: no test-env branch in `lib/`, no config a
  deployment could set to the same effect. What reaches the endpoint is indistinguishable
  from what reaches it in production, which is the point — a test that authenticated some
  other way would be asserting about a request nobody ever makes.

  ## Why it wraps rather than forwards

  `nginx` cannot do this job for a test. It is a container of its own and reaches the
  application by the hostname `app`, which belongs to the long-running service; the
  container a test runs in has no such alias, so nothing outside it can route to its
  endpoint.

  Everything is therefore inside one container — the browser, its driver, and this — and
  with that true the simplest arrangement is not a proxy at all. This is a plug in front
  of the endpoint's own pipeline, served by one listener. Nothing re-issues the request,
  so nothing has to carry a WebSocket upgrade across a second connection: the live socket
  upgrades on the only connection there is.

  ## Who it says you are

  The same cookie the development proxy reads, so the two behave alike and a test choosing
  a principal does it the way a person does in a browser. A request that names nobody is
  the default subject rather than an anonymous one, because the proxy this stands for
  never forwards a request it has not authenticated.
  """

  @behaviour Plug

  @subject_cookie "pluteus_dev_subject"

  @doc """
  The subject asserted for a request that names none.
  """
  @spec default_subject() :: String.t()
  def default_subject, do: "browser@household.test"

  @doc """
  The cookie a request sets to be somebody else.
  """
  @spec subject_cookie() :: String.t()
  def subject_cookie, do: @subject_cookie

  @doc """
  The port this answers on, which is the endpoint's own configured one — it serves that
  endpoint and the endpoint runs no listener of its own, so there is nothing to collide
  with.
  """
  @spec port() :: pos_integer()
  def port do
    :pluteus
    |> Application.fetch_env!(PluteusWeb.Endpoint)
    |> Keyword.fetch!(:http)
    |> Keyword.fetch!(:port)
  end

  @doc """
  Where a browser reaches the interface.
  """
  @spec url(String.t()) :: String.t()
  def url(path \\ "/"), do: "http://127.0.0.1:#{port()}#{path}"

  @impl Plug
  def init(_opts), do: PluteusWeb.Endpoint.init([])

  @impl Plug
  def call(conn, endpoint) do
    config = Application.fetch_env!(:pluteus, PluteusWeb.ForwardAuth)
    conn = Plug.Conn.fetch_cookies(conn)

    conn
    # Set rather than added, as the development proxy sets them: a header a browser sent
    # under the same name is replaced and never arrives twice, which the deployment reads
    # as no identity at all rather than as one.
    |> Plug.Conn.put_req_header(
      Keyword.fetch!(config, :secret_header),
      Keyword.fetch!(config, :secret)
    )
    |> Plug.Conn.put_req_header(
      Keyword.fetch!(config, :subject_header),
      conn.cookies[@subject_cookie] || default_subject()
    )
    |> PluteusWeb.Endpoint.call(endpoint)
  end
end
