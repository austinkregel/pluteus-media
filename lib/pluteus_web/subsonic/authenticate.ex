defmodule PluteusWeb.Subsonic.Authenticate do
  @moduledoc """
  Authenticates a request on the OpenSubsonic surface by client key
  (spec-07 §3.2, §6.1).

  The request must first have come through the proxy; nothing else about it is
  read until then. Then, in this order: a password or a salted token is
  refused with error 42, since the deployment holds no password to check one
  against; `u` given with `apiKey` with error 43; no key with error 10; and a
  key no device holds, whose device is revoked, or whose principal is retired,
  with error 44.
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
      authenticate(conn, credential(conn.params))
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

  defp credential(params) do
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

  defp authenticate(conn, {:key, key}) do
    case Principals.for_key(key) do
      {:ok, principal, device} -> conn |> assign(:principal, principal) |> assign(:device, device)
      {:error, :invalid_key} -> refuse(conn, 44, "Invalid API key")
    end
  end

  defp refuse(conn, code, message), do: conn |> Response.error(code, message) |> halt()
end
