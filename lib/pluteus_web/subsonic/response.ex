defmodule PluteusWeb.Subsonic.Response do
  @moduledoc """
  The `subsonic-response` envelope, in XML by default and in JSON on `f=json`
  (spec-07 §6.1).

  A body is a map. Within it a scalar is an attribute in XML and a field in
  JSON; a map is a child element; a list of maps is a repeated child element;
  and `value` is an element's text in XML, as Subsonic writes a genre's name or
  a lyric line.

  Subsonic answers an error with HTTP 200 and `status: failed`; so does this.
  """

  import Plug.Conn

  @version "1.16.1"

  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Sends a successful response carrying `body` under `key`, or nothing further
  where `key` is nil.
  """
  @spec ok(Plug.Conn.t(), String.t() | nil, map()) :: Plug.Conn.t()
  def ok(conn, nil, _body), do: send_envelope(conn, "ok", %{})
  def ok(conn, key, body), do: send_envelope(conn, "ok", %{key => body})

  @doc """
  Sends an error. A refusal of the authentication a client offered carries
  where a person can get a key it would accept, where the deployment is
  configured with somewhere to send them ([OPENSUBSONIC] apiKeyAuthentication).
  """
  @spec error(Plug.Conn.t(), non_neg_integer(), String.t()) :: Plug.Conn.t()
  def error(conn, code, message) do
    error = %{"code" => code, "message" => message}

    error =
      case {code, help_url()} do
        {code, url} when code in [41, 42] and is_binary(url) -> Map.put(error, "helpUrl", url)
        _no_help -> error
      end

    send_envelope(conn, "failed", %{"error" => error})
  end

  defp help_url, do: :pluteus |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(:help_url)

  defp send_envelope(conn, status, content) do
    envelope =
      Map.merge(
        %{
          "status" => status,
          "version" => @version,
          "type" => "pluteus",
          "serverVersion" => :pluteus |> Application.spec(:vsn) |> to_string(),
          "openSubsonic" => true
        },
        content
      )

    case conn.params["f"] do
      "json" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{"subsonic-response" => present(envelope)}))

      _xml ->
        conn
        |> put_resp_content_type("text/xml")
        |> send_resp(200, [
          ~s(<?xml version="1.0" encoding="UTF-8"?>),
          element("subsonic-response", Map.put(envelope, "xmlns", "http://subsonic.org/restapi"))
        ])
    end
  end

  # An absent field is left out, as XML leaves out a nil attribute.
  defp present(%{} = map), do: for({k, v} <- map, not is_nil(v), into: %{}, do: {k, present(v)})
  defp present(list) when is_list(list), do: Enum.map(list, &present/1)
  defp present(value), do: value

  defp element(name, %{} = content) do
    {text, fields} = Map.pop(content, "value")

    {children, attributes} =
      Enum.split_with(fields, fn {_key, value} -> is_map(value) or is_list(value) end)

    attributes =
      for {key, value} <- Enum.sort(attributes),
          not is_nil(value),
          do: [" ", key, ~s(="), escape(value), ~s(")]

    inner =
      Enum.map(Enum.sort(children), fn
        {key, list} when is_list(list) -> Enum.map(list, &element(key, &1))
        {key, map} -> element(key, map)
      end)

    body = if text, do: [escape(text) | inner], else: inner

    case body do
      [] -> ["<", name, attributes, "/>"]
      _ -> ["<", name, attributes, ">", body, "</", name, ">"]
    end
  end

  defp element(name, scalar), do: element(name, %{"value" => scalar})

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace(~s("), "&quot;")
  end
end
