defmodule PluteusWeb.Declared do
  @moduledoc """
  Asks which surface this is before anything renders (spec-10 §4.4).

  §4.4 requires the surface be declared, forbids inferring one, and says that where no
  declaration exists "the deployment asks before it renders. It does not choose." A
  rendered surface therefore cannot be served to a device that has not said what it is.

  This is a plug rather than a line in each surface because every surface owes the same
  thing, and it sits on the pipeline that answers only HTML. It is not on `:api`, where
  the same URI answers a representation for which §4.4 has nothing to say: a JSON client
  is not a surface and redirecting it would refuse it something it may have.
  """

  @behaviour Plug

  import Plug.Conn, only: [halt: 1]

  alias PluteusWeb.Surface

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{assigns: %{distance: nil}} = conn, _opts), do: conn |> Surface.ask() |> halt()

  @impl Plug
  def call(conn, _opts), do: conn
end
