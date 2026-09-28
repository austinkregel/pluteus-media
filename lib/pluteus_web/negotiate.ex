defmodule PluteusWeb.Negotiate do
  @moduledoc """
  Whether a request asked for the interface or for the representation (spec-07 §4.1).

  §4.1 puts the negotiation "on the presence of `text/html` in the header, not on a
  media-type preference list", and states the failure it is avoiding: "A framework that
  treats `*/*` as matching HTML will serve HTML to every programmatic client, because
  `*/*` is what a command-line client, a fetch call and most HTTP libraries send by
  default."

  So the header is read for the media types it names, and `text/html` is looked for among
  them by name. A quality parameter names no media type and is dropped. `*/*` and
  `text/*` are not `text/html`.

  A client that cannot set the header names `_format=html` instead, which §4.1 honours.
  A selector parser ignores a query parameter naming no selector dimension, so that
  parameter reaches the deep link as nothing.
  """

  @behaviour Plug

  import Plug.Conn

  @html "text/html"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    asked = interface?(conn)

    conn
    |> assign(:interface?, asked)
    |> Phoenix.Controller.put_format(if asked, do: "html", else: "json")
  end

  @doc """
  Whether a request asked for the interface.
  """
  @spec interface?(Plug.Conn.t()) :: boolean()
  def interface?(conn) do
    named_html?(conn) or @html in media_types(conn)
  end

  defp named_html?(conn) do
    fetch_query_params(conn).query_params["_format"] == "html"
  end

  defp media_types(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&media_type/1)
  end

  # A media type's parameters are not part of its name, so `text/html;q=0.9` and
  # `text/html` name one type. [RFC9110] §8.3.1 makes a type and a subtype
  # case-insensitive.
  defp media_type(value) do
    value |> String.split(";") |> hd() |> String.trim() |> String.downcase()
  end
end
