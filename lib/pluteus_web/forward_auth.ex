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

    with :ok <- from_proxy(conn, config),
         {:ok, identity} <- identity(conn, config) do
      conn = assign(conn, :identity, identity)
      if require_principal, do: attach_principal(conn, identity), else: conn
    else
      {:error, reason} -> refuse(conn, 401, "unauthenticated", reason)
    end
  end

  defp from_proxy(conn, config) do
    expected = Keyword.fetch!(config, :secret)

    case get_req_header(conn, Keyword.fetch!(config, :secret_header)) do
      [presented] ->
        if Plug.Crypto.secure_compare(presented, expected),
          do: :ok,
          else: {:error, "the request did not come through the authenticating proxy"}

      _absent_or_repeated ->
        {:error, "the request did not come through the authenticating proxy"}
    end
  end

  defp identity(conn, config) do
    case get_req_header(conn, Keyword.fetch!(config, :subject_header)) do
      [subject] when subject != "" -> {:ok, {Keyword.fetch!(config, :issuer), subject}}
      _absent_or_repeated -> {:error, "the proxy supplied no identity"}
    end
  end

  defp attach_principal(conn, {issuer, subject}) do
    case Principals.admit(issuer, subject) do
      %Principal{retired_at: retired} when not is_nil(retired) ->
        refuse(conn, 403, "retired", "this principal has been removed from the household")

      %Principal{} = principal ->
        assign(conn, :principal, principal)
    end
  end

  defp refuse(conn, status, type, detail) do
    conn
    |> Problem.send(status, %{type: Problem.type(type), title: type, detail: detail})
    |> halt()
  end
end
