defmodule PluteusWeb.SubsonicController do
  @moduledoc """
  The OpenSubsonic surface (spec-07 §6): one action that dispatches on the
  endpoint named in the path, with or without Subsonic's `.view` suffix.

  An endpoint this surface does not provide answers error 0 naming it. It never
  answers with an empty success: a client told there are no podcasts is misled,
  and one told the endpoint is not provided can say so.
  """

  use PluteusWeb, :controller

  alias Pluteus.Authorization
  alias PluteusWeb.Subsonic.Browse
  alias PluteusWeb.Subsonic.Lists
  alias PluteusWeb.Subsonic.Own
  alias PluteusWeb.Subsonic.Response
  alias PluteusWeb.Subsonic.Retrieval

  @extensions [
    %{"name" => "apiKeyAuthentication", "versions" => [1]},
    %{"name" => "formPost", "versions" => [1]},
    %{"name" => "songLyrics", "versions" => [1]},
    %{"name" => "indexBasedQueue", "versions" => [1]}
  ]

  @doc """
  The extensions `getOpenSubsonicExtensions` advertises, and no others
  (spec-07 §6.2).
  """
  @spec extensions() :: [map()]
  def extensions, do: @extensions

  @surfaces [Browse, Lists, Retrieval, Own]

  @doc """
  The surfaces whose endpoints carry a grant.
  """
  @spec surfaces() :: [module()]
  def surfaces, do: @surfaces

  @doc """
  The endpoints answerable with nothing granted (spec-06 §4.2).

  Each reports what this deployment is rather than anything the household holds, so
  there is nothing for a grant to be about. Pinned here so the set cannot grow
  quietly.
  """
  @spec ungranted() :: [String.t()]
  def ungranted, do: ~w(ping getLicense getOpenSubsonicExtensions tokenInfo)

  def dispatch(conn, %{"endpoint" => endpoint}) do
    endpoint = String.replace_suffix(endpoint, ".view", "")

    case Enum.find(@surfaces, &(endpoint in &1.endpoints())) do
      nil -> handle(endpoint, conn)
      surface -> permitted(conn, surface, endpoint)
    end
  end

  # spec-07 §3.4: a key's grant "is checked on every request", and this is the one
  # point every key-authenticated request passes through. Error 50 is what §6.8
  # maps "the requesting principal may not" to.
  defp permitted(conn, surface, endpoint) do
    credential = conn.assigns.credential

    case Enum.reject(surface.operations(endpoint), &Authorization.granted?(credential, &1)) do
      [] ->
        surface.handle(endpoint, conn)

      [refused | _rest] ->
        Response.error(conn, 50, "This credential does not grant #{refused}")
    end
  end

  defp handle("ping", conn), do: Response.ok(conn, nil, %{})

  defp handle("getLicense", conn),
    do: Response.ok(conn, "license", %{"valid" => true})

  defp handle("getOpenSubsonicExtensions", conn),
    do: Response.ok(conn, "openSubsonicExtensions", @extensions)

  defp handle("tokenInfo", conn),
    do: Response.ok(conn, "tokenInfo", %{"username" => conn.assigns.principal.id})

  defp handle(endpoint, conn),
    do: Response.error(conn, 0, "The endpoint #{endpoint} is not provided by this server")
end
