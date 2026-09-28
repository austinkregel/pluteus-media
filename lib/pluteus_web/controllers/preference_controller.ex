defmodule PluteusWeb.PreferenceController do
  @moduledoc """
  What a principal has chosen about how things are shown to them
  (spec-10 §14.5, §17.4, §17.8, §12.4, §9.2).

  The path names no principal. It answers the requesting one and there is no
  request that could ask for another's, which is what §14.5 needs: "A principal's
  caption styling, motion preference, contrast preference, text size and
  described-audio default are that principal's and MUST NOT be visible to another."
  §21 restates it — "per principal and are not household-visible". `/devices` takes
  the same shape for the same kind of reason.

  That is why there is no `/principals/{id}/preferences`. A path carrying another
  principal's identifier would need a refusal, and spec-07 §4.5 makes the refusal
  itself a disclosure: a 403 "would confirm that another principal's datum exists".
  A path that cannot express the question needs no answer to it.

  Every key is answered, with the registry's default where the principal has set
  nothing, so a client never carries a default of its own and an unset preference
  and a defaulted one are the same thing on the wire.
  """

  use PluteusWeb, :controller

  alias Pluteus.Preferences
  alias Pluteus.Preferences.Registry
  alias PluteusWeb.Problem

  def index(conn, _params) do
    json(conn, %{"preferences" => Preferences.held_by(conn.assigns.principal.id)})
  end

  def update(conn, %{"preferences" => values}) when is_map(values) and map_size(values) > 0 do
    case unknown(values) do
      [] -> write(conn, values)
      [key | _rest] -> invalid(conn, "#{key} is not a preference")
    end
  end

  def update(conn, _params) do
    invalid(conn, "preferences names what to set, as an object of at least one key")
  end

  defp write(conn, values) do
    case Preferences.set_many(conn.assigns.principal.id, values) do
      {:ok, held} ->
        json(conn, %{"preferences" => held})

      {:error, key, changeset} ->
        refused(conn, key, changeset)
    end
  end

  # A value outside its key's domain is a constraint refusing the write, which
  # spec-07 §4.5 answers 422 "naming it". The domain is named rather than the value
  # echoed, so a client can offer the choices rather than guess at them.
  defp refused(conn, key, changeset) do
    Problem.send(conn, 422, %{
      type: Problem.type("constraint"),
      title: "constraint",
      detail: detail(key, changeset),
      preference: key,
      admits: Registry.domain(key)
    })
  end

  defp detail(key, changeset) do
    case changeset.errors[:value] do
      {message, _opts} -> "#{key} #{message}"
      nil -> "#{key} cannot be set to that"
    end
  end

  defp unknown(values) do
    known = Registry.keys()

    values |> Map.keys() |> Enum.reject(&(&1 in known))
  end

  defp invalid(conn, detail) do
    Problem.send(conn, 400, %{
      type: Problem.type("invalid-request"),
      title: "invalid-request",
      detail: detail
    })
  end
end
