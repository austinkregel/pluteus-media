defmodule PluteusWeb.ForwardAuth do
  @moduledoc """
  Establishes who a request is from, as a reverse proxy running forward auth
  has already decided.

  The proxy asks the identity provider about every request and, on success,
  copies the provider's identity headers onto the request it forwards
  (Authentik's outpost headers, which aut.hair also sets). Pluteus runs no
  login flow of its own; it reads those headers.

  Headers are only trustworthy from the proxy. Anything that reaches Pluteus
  another way — a published port, the container network — could set them, so a
  request must also carry a secret the proxy injects and clients cannot supply.
  Without it the identity headers are not read at all.

  The identity is the `(issuer, subject)` pair of spec-06 §3.2. The issuer is
  the configured provider; the subject is read from the configured header.

  The provider has already decided the person may use the deployment — that is
  what its letting the request through means — so an identity arriving for the
  first time becomes a Member (§6.1). A principal an Administrator has retired
  is refused even so.

  Pass `require_principal: false` for onboarding, which reads the identity and
  decides for itself what to make of it.
  """

  @behaviour Plug

  import Plug.Conn

  alias Pluteus.Principals
  alias Pluteus.Principals.Principal
  alias PluteusWeb.Problem

  @impl Plug
  def init(opts), do: Keyword.get(opts, :require_principal, true)

  @impl Plug
  def call(conn, require_principal) do
    config = Application.fetch_env!(:pluteus, __MODULE__)

    with :ok <- from_proxy(conn.req_headers, config),
         {:ok, identity} <- identity(conn.req_headers, config) do
      conn = assign(conn, :identity, identity)
      if require_principal, do: attach_principal(conn, identity), else: conn
    else
      {:error, reason} -> refuse(conn, 401, "unauthenticated", reason)
    end
  end

  @doc """
  The principal a set of request headers establishes, as `call/2` would
  attach it. The socket (spec-07 §5.2) authenticates its upgrade request with
  this, from the headers it is given.
  """
  @spec principal([{String.t(), String.t()}]) ::
          {:ok, Principal.t()} | {:error, String.t(), String.t()}
  def principal(headers) do
    config = Application.fetch_env!(:pluteus, __MODULE__)

    with :ok <- from_proxy(headers, config),
         {:ok, identity} <- identity(headers, config) do
      admitted(identity)
    else
      {:error, reason} -> {:error, "unauthenticated", reason}
    end
  end

  @doc """
  Whether a request came through the authenticating proxy: it carries the
  secret the proxy injects, once. The surface exempt from forward
  authentication (spec-07 §3.2) still asks this before reading anything else.
  """
  @spec from_proxy?(Plug.Conn.t()) :: boolean()
  def from_proxy?(conn),
    do: from_proxy(conn.req_headers, Application.fetch_env!(:pluteus, __MODULE__)) == :ok

  @doc """
  Whether the proxy's secret header is on the request at all, whatever its value.

  A surface that renders for a household with no principal has to tell a request that
  never went through the proxy from one carrying a secret that does not match. The
  first is anonymous; the second is a forgery or a misconfigured proxy. `from_proxy?/1`
  answers `false` to both, which is right where a valid secret is the only question and
  wrong where the alternative to refusing is rendering.
  """
  @spec secret_presented?(Plug.Conn.t()) :: boolean()
  def secret_presented?(conn) do
    config = Application.fetch_env!(:pluteus, __MODULE__)

    values(conn.req_headers, Keyword.fetch!(config, :secret_header)) != []
  end

  defp from_proxy(headers, config) do
    expected = Keyword.fetch!(config, :secret)

    case values(headers, Keyword.fetch!(config, :secret_header)) do
      [presented] ->
        if Plug.Crypto.secure_compare(presented, expected),
          do: :ok,
          else: {:error, "the request did not come through the authenticating proxy"}

      _absent_or_repeated ->
        {:error, "the request did not come through the authenticating proxy"}
    end
  end

  defp identity(headers, config) do
    case values(headers, Keyword.fetch!(config, :subject_header)) do
      [subject] when subject != "" -> {:ok, {Keyword.fetch!(config, :issuer), subject}}
      _absent_or_repeated -> {:error, "the proxy supplied no identity"}
    end
  end

  defp values(headers, name), do: for({^name, value} <- headers, do: value)

  defp attach_principal(conn, identity) do
    case admitted(identity) do
      {:ok, principal} -> assign(conn, :principal, principal)
      {:error, type, detail} -> refuse(conn, 403, type, detail)
    end
  end

  defp admitted({issuer, subject}) do
    case Principals.admit(issuer, subject) do
      %Principal{retired_at: retired} when not is_nil(retired) ->
        {:error, "retired", "this principal has been removed from the household"}

      %Principal{} = principal ->
        {:ok, principal}
    end
  end

  defp refuse(conn, status, type, detail) do
    conn
    |> Problem.send(status, %{type: Problem.type(type), title: type, detail: detail})
    |> halt()
  end
end
