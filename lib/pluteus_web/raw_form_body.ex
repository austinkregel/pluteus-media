defmodule PluteusWeb.RawFormBody do
  @moduledoc """
  Keeps a form body as it arrived, alongside the parsed parameters.

  Subsonic clients repeat a parameter to give several values — `id=a&id=b` —
  and a parsed form keeps only the last. The OpenSubsonic surface accepts every
  endpoint by form POST (spec-07 §6.2, `formPost`), so it reads repeated values
  from the body as it arrived.
  """

  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {status, chunk, conn} when status in [:ok, :more] ->
        kept = [Map.get(conn.private, :raw_form_body, []), chunk]
        {status, chunk, Plug.Conn.put_private(conn, :raw_form_body, kept)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
