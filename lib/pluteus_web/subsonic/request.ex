defmodule PluteusWeb.Subsonic.Request do
  @moduledoc """
  Reading a request on the OpenSubsonic surface: its parameters, repeated ones
  included, and the profile its names resolve under.

  A reader returns `{:ok, value}` or `{:error, code, message}` with the
  Subsonic error the condition answers (spec-07 §6.8): a required parameter
  missing is 10, and an identifier naming nothing this surface serves is 70.
  """

  alias Pluteus.Catalog.Profile

  @type result(value) :: {:ok, value} | {:error, non_neg_integer(), String.t()}

  @doc """
  The resolution profile: the requesting principal's own person as assigner,
  where it has one.
  """
  @spec profile(Plug.Conn.t()) :: Profile.t()
  def profile(conn), do: %Profile{assigner_id: conn.assigns.principal.person_id}

  @doc """
  Every value of a parameter, from the query string and a form body, in order.
  """
  @spec all(Plug.Conn.t(), String.t()) :: [String.t()]
  def all(conn, key) do
    body = conn.private |> Map.get(:raw_form_body, []) |> IO.iodata_to_binary()

    for source <- [conn.query_string, body],
        {^key, value} <- URI.query_decoder(source),
        do: value
  end

  @spec optional(Plug.Conn.t(), String.t()) :: String.t() | nil
  def optional(conn, key), do: conn.params[key]

  @spec required(Plug.Conn.t(), String.t()) :: result(String.t())
  def required(conn, key) do
    case conn.params[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> missing(key)
    end
  end

  @doc """
  A required identifier. One that is not an identifier at all names nothing,
  and answers 70 as an unknown one does.
  """
  @spec id(Plug.Conn.t(), String.t()) :: result(Ecto.UUID.t())
  def id(conn, key) do
    with {:ok, value} <- required(conn, key), do: uuid(value)
  end

  @doc """
  Every value of a repeated identifier parameter.
  """
  @spec ids(Plug.Conn.t(), String.t()) :: result([Ecto.UUID.t()])
  def ids(conn, key) do
    conn
    |> all(key)
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case uuid(value) do
        {:ok, id} -> {:cont, {:ok, [id | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      error -> error
    end
  end

  @spec uuid(String.t()) :: result(Ecto.UUID.t())
  def uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> not_found(value)
    end
  end

  @doc """
  An integer parameter, `default` where absent, refused outside `range`.
  """
  @spec integer(Plug.Conn.t(), String.t(), integer() | nil, Range.t()) :: result(integer() | nil)
  def integer(conn, key, default, range) do
    case conn.params[key] do
      nil -> {:ok, default}
      value -> within(Integer.parse(value), key, range)
    end
  end

  defp within({number, ""}, key, range) do
    if number in range,
      do: {:ok, number},
      else: {:error, 0, "#{key} must be from #{range.first} to #{range.last}"}
  end

  defp within(_not_whole, key, _range), do: {:error, 0, "#{key} must be a whole number"}

  @spec boolean(Plug.Conn.t(), String.t(), boolean()) :: result(boolean())
  def boolean(conn, key, default) do
    case conn.params[key] do
      nil -> {:ok, default}
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _other -> {:error, 0, "#{key} must be true or false"}
    end
  end

  @spec missing(String.t()) :: {:error, 10, String.t()}
  def missing(key), do: {:error, 10, "Required parameter is missing: #{key}"}

  @spec not_found(String.t()) :: {:error, 70, String.t()}
  def not_found(id), do: {:error, 70, "The requested data was not found: #{id}"}
end
