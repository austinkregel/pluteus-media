defmodule PluteusWeb.Native do
  @moduledoc """
  What the native API's controllers share (spec-07 §4): the path each res
  kind is served under, the resolution profile a request reads names with,
  paging, and how a write is attributed and how its refusal is answered.
  """

  import Plug.Conn

  alias Pluteus.Actor
  alias Pluteus.Catalog.Profile
  alias PluteusWeb.Problem

  @paths %{
    work: "works",
    expression: "expressions",
    manifestation: "manifestations",
    item: "items",
    digital_item: "digital-items",
    asset: "assets",
    person: "persons",
    collective_agent: "collective-agents",
    place: "places",
    time_span: "time-spans",
    nomen: "nomens",
    address: "addresses",
    annotation: "annotations"
  }

  @default_limit 50
  @maximum_limit 500

  @doc """
  Every res kind the native API serves, with the path it is served under.
  """
  @spec paths() :: %{atom() => String.t()}
  def paths, do: @paths

  @doc """
  The resolution profile a request reads names with: the requesting principal's
  own person as assigner, where it has one, and no language preference, unless
  the request names `language` or `assigner`.
  """
  @spec profile(Plug.Conn.t()) :: Profile.t()
  def profile(conn) do
    %Profile{
      language: conn.params["language"],
      assigner_id: conn.params["assigner"] || conn.assigns.principal.person_id
    }
  end

  @doc """
  The page a collection request asks for: its `limit`, at most
  #{@maximum_limit}, and the identifier it continues `after`.
  """
  @spec page(Plug.Conn.t()) :: {:ok, pos_integer(), Ecto.UUID.t() | nil} | {:error, String.t()}
  def page(conn) do
    with {:ok, limit} <- limit(conn.params["limit"]),
         {:ok, after_id} <- after_id(conn.params["after"]) do
      {:ok, limit, after_id}
    end
  end

  defp limit(nil), do: {:ok, @default_limit}

  defp limit(value) do
    case Integer.parse(value) do
      {limit, ""} when limit in 1..@maximum_limit -> {:ok, limit}
      _other -> {:error, "limit must be a whole number from 1 to #{@maximum_limit}"}
    end
  end

  defp after_id(nil), do: {:ok, nil}

  defp after_id(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, "after must be an identifier"}
    end
  end

  @doc """
  Runs a write attributed to the requesting principal. A write a changeset
  refuses is answered 422 naming each field and, where a constraint refused
  it, the constraint; a write that raises is not caught, and answers 500.
  """
  @spec write(Plug.Conn.t(), (-> {:ok, term()} | {:error, term()}), (Plug.Conn.t(), term() ->
                                                                       Plug.Conn.t())) ::
          Plug.Conn.t()
  def write(conn, fun, respond) do
    case Actor.as(conn.assigns.principal.id, fun) do
      {:ok, result} -> respond.(conn, result)
      {:error, %Ecto.Changeset{} = changeset} -> refused(conn, changeset_errors(changeset))
      {:error, reason} -> refused(conn, %{reason: inspect(reason)})
    end
  end

  defp refused(conn, detail) do
    Problem.send(conn, 422, %{
      type: Problem.type("constraint"),
      title: "constraint",
      detail: detail
    })
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      text =
        Enum.reduce(opts, message, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)

      case opts[:constraint_name] do
        nil -> %{message: text}
        constraint -> %{message: text, constraint: constraint}
      end
    end)
  end

  @spec invalid(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def invalid(conn, detail),
    do:
      Problem.send(conn, 400, %{
        type: Problem.type("invalid-request"),
        title: "invalid-request",
        detail: detail
      })

  @spec not_found(Plug.Conn.t()) :: Plug.Conn.t()
  def not_found(conn),
    do: Problem.send(conn, 404, %{type: Problem.type("not-found"), title: "not-found"})

  @spec created(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def created(conn, body), do: conn |> put_status(201) |> Phoenix.Controller.json(body)
end
