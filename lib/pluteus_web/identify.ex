defmodule PluteusWeb.Identify do
  @moduledoc """
  Attaches the principal to a rendered request, where the proxy has named one.

  The native API requires a principal of every request (spec-07 §3.4) and
  `PluteusWeb.ForwardAuth` refuses one without. A rendered surface cannot: spec-10
  Annex A.8.1 puts a licence obligation in the interface and the design language is
  household-public, so those pages answer a request that carries no identity at all.

  Three cases, and the middle one is why this is a plug rather than an option on
  `ForwardAuth`:

    * no secret header — the request did not come through the proxy. It renders with
      no principal, and a surface that needs one asks for it.
    * a secret header that does not match, or a matching one with no identity — a
      forgery, or a proxy configured wrongly. Refused. A bad secret is never treated
      as an absent one, because that would make a forged header the same as none and
      hand an anonymous render to whoever guessed at the header's name.
    * a matching secret naming an admitted principal — attached.

  The refusal is a problem document rather than a page. There is one refusal
  mechanism in the deployment rather than two, and neither of the conditions that
  reach it is a person's path through the interface.
  """

  @behaviour Plug

  import Plug.Conn

  alias PluteusWeb.ForwardAuth
  alias PluteusWeb.Problem

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if ForwardAuth.secret_presented?(conn) do
      attach(conn)
    else
      assign(conn, :principal, nil)
    end
  end

  defp attach(conn) do
    case ForwardAuth.principal(conn.req_headers) do
      {:ok, principal} -> assign(conn, :principal, principal)
      {:error, type, detail} -> refuse(conn, type, detail)
    end
  end

  defp refuse(conn, type, detail) do
    conn
    |> Problem.send(status(type), %{
      type: Problem.type(type),
      title: type,
      detail: detail
    })
    |> halt()
  end

  # The same statuses `ForwardAuth` answers, from the same two reasons. A third kind of
  # refusal raises here rather than being given a status nobody chose.
  defp status("unauthenticated"), do: 401
  defp status("retired"), do: 403
end
