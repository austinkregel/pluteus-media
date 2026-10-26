defmodule PluteusWeb.Live.Search do
  @moduledoc """
  The chrome's search field, answered on every surface ([spec-10] §9.5, criterion 52).

  §9.5 requires search to be reachable from every mode, and reaching it to keep the
  active facet set. The field is the chrome's, so the surface it is drawn on receives its
  submission whichever surface that is; this answers it in one place for all of them, by
  navigating to the search the form describes. A navigation and not a page load, so what
  the transport is playing goes on playing.

  The form carries the mode and the facets of the surface it was submitted from as well
  as the term, which is what makes the search one more term over the current selection
  rather than a fresh query.

  The hook answers only the search event and hands every other event on untouched: it is
  attached to every surface, and the surface's own handlers are the ones that answer the
  rest.
  """

  import Phoenix.LiveView

  alias Pluteus.Browse.Query
  alias PluteusWeb.Chrome

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :search, :handle_event, &searched/3)}
  end

  # The form's own parameters, so a refusal here is a field the chrome drew wrongly and
  # raises rather than being answered with a search nobody asked for.
  defp searched("search", params, socket) do
    {:ok, query} = Query.parse_search(params)

    {:halt, push_navigate(socket, to: Chrome.searched_at(query))}
  end

  defp searched(_event, _params, socket), do: {:cont, socket}
end
