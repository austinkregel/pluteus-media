defmodule PluteusWeb.SubsonicController do
  @moduledoc """
  The OpenSubsonic surface (spec-07 §6): one action that dispatches on the
  endpoint named in the path, with or without Subsonic's `.view` suffix.

  An endpoint this surface does not provide answers error 0 naming it. It never
  answers with an empty success: a client told there are no podcasts is misled,
  and one told the endpoint is not provided can say so.
  """

  use PluteusWeb, :controller

  alias PluteusWeb.Subsonic.Response

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

  def dispatch(conn, %{"endpoint" => endpoint}) do
    endpoint |> String.replace_suffix(".view", "") |> handle(conn)
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
