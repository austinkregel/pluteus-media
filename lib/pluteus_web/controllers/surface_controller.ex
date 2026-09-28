defmodule PluteusWeb.SurfaceController do
  @moduledoc """
  Asking which surface the interface is being rendered on, and recording the answer
  (spec-10 §4.4).

  §4.4 makes this a declaration and forbids inferring it, so where a device has declared
  nothing the deployment asks before it renders.

  A surface is not a res, so §10.1 gives it a path of its own. `return_to` carries the
  address the person was reaching for, and answering the question puts them there.
  """

  use PluteusWeb, :controller

  alias PluteusWeb.Surface

  # What each context is said by. A.1.6 names the contexts; the words asking about them
  # are this deployment's, and they describe the screen.
  @said %{
    "near" => {"Close up", "A phone, a tablet, a laptop or a monitor on a desk."},
    "far" => {"Across the room", "A television or a projector, read from a few metres away."}
  }

  def ask(conn, params) do
    render(conn, :ask,
      page_title: "Which screen is this?",
      return_to: local(params["return_to"]),
      choices: for(distance <- Surface.contexts(), do: choice(distance))
    )
  end

  def declare(conn, %{"distance" => distance} = params) do
    conn
    |> Surface.declare(distance)
    |> redirect(to: local(params["return_to"]))
  end

  defp choice(distance) do
    {said, how} = Map.fetch!(@said, distance)

    {distance, said, how}
  end

  # A path of this deployment's own, never a URL a request supplied: a question that
  # returns somewhere else on being answered is an open redirect.
  defp local("/" <> rest), do: "/" <> String.replace_prefix(rest, "/", "")
  defp local(_elsewhere_or_absent), do: "/"
end
