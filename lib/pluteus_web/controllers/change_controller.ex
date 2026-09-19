defmodule PluteusWeb.ChangeController do
  @moduledoc """
  `GET /changes?after={n}` (spec-07 §5.1): each released catalog write after
  `n`, in order, with the res it touched. `released` is how far the feed then
  reached; a client that has read through it has seen every write so far.
  """

  use PluteusWeb, :controller

  alias Pluteus.Changes
  alias Pluteus.Changes.Release
  alias PluteusWeb.Native

  def index(conn, params) do
    with {:ok, after_number} <- after_number(params["after"]),
         {:ok, limit} <- Native.limit(params["limit"]) do
      released = Release.released()

      json(conn, %{
        "changes" => Changes.feed(after_number, limit, released),
        "released" => released
      })
    else
      {:error, detail} -> Native.invalid(conn, detail)
    end
  end

  defp after_number(nil), do: {:ok, 0}

  defp after_number(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> {:ok, number}
      _other -> {:error, "after must be a whole number"}
    end
  end
end
