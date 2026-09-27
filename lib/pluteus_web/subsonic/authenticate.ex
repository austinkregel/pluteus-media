defmodule PluteusWeb.Subsonic.Authenticate do
  @moduledoc """
  Authenticates a request on the OpenSubsonic surface by client key
  (spec-07 §3.2, §6.1).

  The request must first have come through the proxy; nothing else about it is
  read until then. A client asking for a protocol newer than this server speaks
  is answered 30 before its credential is read: what it would do with the answer
  is not this server's to guess.

  A key may arrive in an `X-API-Key` header instead of the query string, which
  keeps it out of the access logs §8 warns of. A header is unambiguous, so a
  username or password the client sent beside it is ignored rather than
  refused: a client with no field for a key, and no way to leave its password
  field empty, is otherwise shut out over a value this deployment never reads.

  Otherwise, in this order: a password or a salted token is refused with error
  42, since the deployment holds no password to check one against; `u` given
  with `apiKey` with error 43; no key with error 10; and a key no device holds,
  whose device is revoked, or whose principal is retired, with error 44.
  """

  @behaviour Plug

  import Plug.Conn

  alias Pluteus.Principals
  alias PluteusWeb.ForwardAuth
  alias PluteusWeb.Problem
  alias PluteusWeb.Subsonic.Response

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if ForwardAuth.from_proxy?(conn) do
      case protocol(conn.params["v"]) do
        :ok -> authenticate(conn, credential(conn))
        {:refuse, code, message} -> refuse(conn, code, message)
      end
    else
      conn
      |> Problem.send(401, %{
        type: Problem.type("unauthenticated"),
        title: "unauthenticated",
        detail: "the request did not come through the authenticating proxy"
      })
      |> halt()
    end
  end

  # spec-07 §6.8: a client asking for a version this server does not speak is
  # answered 30, which names the server as the one that must upgrade.
  defp protocol(nil), do: :ok

  defp protocol(asked) do
    if version(asked) <= version(Response.version()),
      do: :ok,
      else: {:refuse, 30, "Incompatible Subsonic REST protocol version. Server must upgrade."}
  end

  defp version(string) do
    string
    |> String.split(".")
    |> Enum.map(fn part ->
      case Integer.parse(part) do
        {number, _rest} -> number
        :error -> 0
      end
    end)
  end

  defp credential(conn) do
    case get_req_header(conn, "x-api-key") do
      [key] -> {:key, key}
      [] -> offered(conn.params)
      _several -> {:refuse, 43, "Multiple conflicting authentication mechanisms provided"}
    end
  end

  defp offered(params) do
    cond do
      Map.has_key?(params, "p") or Map.has_key?(params, "t") ->
        {:refuse, 42, "Provided authentication mechanism not supported: use apiKey"}

      Map.has_key?(params, "u") and Map.has_key?(params, "apiKey") ->
        {:refuse, 43, "Multiple conflicting authentication mechanisms provided"}

      Map.has_key?(params, "apiKey") ->
        {:key, params["apiKey"]}

      true ->
        {:refuse, 10, "Required parameter is missing: apiKey"}
    end
  end

  defp authenticate(conn, {:refuse, code, message}), do: refuse(conn, code, message)

  # A key names one credential, and the request acts as that credential's
  # principal and no other (spec-07 §3.3, §3.4). The credential is assigned
  # because what the request may do is recorded on it (spec-06 §4.2), and a
  # revoked one is refused whatever else its device holds (§4.1).
  defp authenticate(conn, {:key, key}) do
    case Principals.for_key(key) do
      {:ok, %{principal: principal, device: device, credential: credential}} ->
        conn
        |> assign(:principal, principal)
        |> assign(:device, device)
        |> assign(:credential, credential)

      {:error, :invalid_key} ->
        refuse(conn, 44, "Invalid API key")
    end
  end

  defp refuse(conn, code, message), do: conn |> Response.error(code, message) |> halt()
end
