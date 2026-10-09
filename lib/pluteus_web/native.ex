defmodule PluteusWeb.Native do
  @moduledoc """
  What the native API's controllers share (spec-07 §4): the path each res
  kind is served under, the resolution profile a request reads names with,
  paging, and how a write is attributed and how its refusal is answered.
  """

  import Plug.Conn

  alias Pluteus.Actor
  alias Pluteus.Catalog.Profile
  alias Pluteus.Preferences
  alias Pluteus.Preferences.Registry
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
    artist: "artists",
    place: "places",
    time_span: "time-spans",
    nomen: "nomens",
    address: "addresses",
    annotation: "annotations"
  }

  @default_limit 50
  @maximum_limit 500

  # [spec-10] §9.1's kinds. It names agents rather than the kinds an agent may be, and
  # there are three: a person, a collective agent, and an artist — which spec-01 §3.1
  # makes an agent of an undetermined one of the two, and which a credit names.
  @interface_kinds ~w(
    work expression manifestation item digital_item
    person collective_agent artist place time_span address
  )a

  @doc """
  Every res kind the native API serves, with the path it is served under.

  Total over the kinds that name a subtype, because §10.1 gives every res an address and
  a surface builds every related address at once: one kind with no path takes a whole page
  down rather than leaving one link out of it.
  """
  @spec paths() :: %{atom() => String.t()}
  def paths, do: @paths

  @doc """
  The one kind that is served under no path.

  `res` is the identifier space itself and names no subtype, so there is no row it
  addresses. Named rather than left as a gap in `paths/0`, so that a kind added to the
  model and not to the table is a failure and not a silent omission.
  """
  @spec addressless() :: [atom()]
  def addressless, do: [:res]

  @doc """
  Whether a kind answers with the interface where a request asks for one ([spec-10] §9.1).

  A nomen, an annotation and an asset do not, per §9.1 and spec-03 §10. Each stays
  reachable as the representation whatever was asked for, and appears in the interface as
  part of the res it belongs to.
  """
  @spec negotiates?(atom()) :: boolean()
  def negotiates?(kind), do: kind in @interface_kinds

  @doc """
  The resolution profile a request reads names with (spec-01 §7.4): the requesting
  principal's own person as assigner, where it has one, and the language range that
  principal holds, unless the request names `language` or `assigner`.

  §7.4 makes the profile per principal and persisted, and a request's own narrowing
  one request's: naming `language` here changes nothing the principal has stored.

  The value the domain reserves for narrowing nothing becomes a nil language, which is
  what `Pluteus.Catalog.Profile` means by no preference. A request may name it too, so
  a client can ask for the unnarrowed resolution whatever the principal holds.

  A request naming `language` with no value asks for the deployment's own language,
  which the registry states.
  """
  @spec profile(Plug.Conn.t()) :: Profile.t()
  def profile(conn) do
    %Profile{
      language: language(conn),
      assigner_id: conn.params["assigner"] || conn.assigns.principal.person_id
    }
  end

  # §7.4's stored range applies where the request does not name a language. Naming it
  # empty asks to be narrowed and names no range to narrow by, so the deployment's own
  # language answers.
  defp language(conn) do
    named =
      case Map.fetch(conn.params, "language") do
        {:ok, ""} -> Registry.empty_request("language")
        {:ok, range} -> range
        :error -> Preferences.held(conn.assigns.principal.id, "language")
      end

    if named == Registry.reserved("language"), do: nil, else: named
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

  @doc """
  A page size as a request gives it, or the default where it gives none.
  """
  @spec limit(String.t() | nil) :: {:ok, pos_integer()} | {:error, String.t()}
  def limit(nil), do: {:ok, @default_limit}

  def limit(value) do
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
