defmodule PluteusWeb.Surface do
  @moduledoc """
  Which surface the interface is being rendered on (spec-10 §4.4).

  §4.4 requires a surface be declared, forbids inferring one, and leaves it undetermined
  where the device has declared none.

  The declaration belongs to the device. A browser reaching the interface has no device
  row — those are minted against a client key (spec-07 §4.3) — so the browser profile is
  the device here and the declaration is a cookie in it, which the server reads before
  anything is rendered.

  A cookie carrying a context `distance` does not declare leaves the surface undetermined.
  """

  @behaviour Plug

  import Plug.Conn

  alias PluteusWeb.Layouts

  @cookie "pluteus_surface"

  # Three years. §4.4 makes the declaration a property of the device rather than of a
  # visit, and a principal may change it in one interaction whenever they like.
  @age 94_608_000

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts), do: assign(conn, :distance, declared(conn))

  @doc """
  The distance this device declares, or nil where it has declared none.
  """
  @spec declared(Plug.Conn.t()) :: String.t() | nil
  def declared(conn) do
    conn = fetch_cookies(conn)

    if conn.cookies[@cookie] in contexts(), do: conn.cookies[@cookie]
  end

  @doc """
  Records a device's declaration.
  """
  @spec declare(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def declare(conn, distance) when is_binary(distance) do
    true = distance in contexts()

    put_resp_cookie(conn, @cookie, distance,
      max_age: @age,
      same_site: "Lax",
      http_only: true
    )
  end

  @doc """
  Every distance a device may declare, as A.1.6's modifier admits them.
  """
  @spec contexts() :: [String.t()]
  def contexts do
    {"distance", contexts} = Enum.find(Layouts.modifiers(), &(elem(&1, 0) == "distance"))

    contexts
  end

  @doc """
  The name of the cookie the declaration is recorded in.
  """
  @spec cookie() :: String.t()
  def cookie, do: @cookie
end
