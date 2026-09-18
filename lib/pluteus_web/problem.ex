defmodule PluteusWeb.Problem do
  @moduledoc """
  Problem details responses [RFC 9457].

  The status line says what happened; the problem type says what kind of thing
  happened, which a status code alone cannot. §14.2 depends on the difference:
  a recycled and a purged entity are both `410 Gone`, and only the type tells a
  client that one of them can still be restored.
  """

  import Plug.Conn

  @doc """
  An absolute URI naming a problem type this system defines.
  """
  @spec type(String.t()) :: String.t()
  def type(name), do: PluteusWeb.Endpoint.url() <> "/problems/" <> name

  @spec send(Plug.Conn.t(), pos_integer(), map()) :: Plug.Conn.t()
  def send(conn, status, fields) do
    body =
      Map.merge(
        %{status: status, instance: conn.request_path},
        fields
      )

    conn
    |> put_resp_content_type("application/problem+json")
    |> send_resp(status, Jason.encode!(body))
  end
end
