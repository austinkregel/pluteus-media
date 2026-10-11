defmodule PluteusWeb.NotFoundError do
  @moduledoc """
  Raised where a path names nothing: an identifier that is not one, a work that is not
  held, or a surface the res's category is not presented on.

  Asking a film to be read is not found rather than answered with something else, which
  spec-10 §10.1 requires of a subordinate path.
  """
  defexception [:message]

  defimpl Plug.Exception do
    def status(_exception), do: 404
    def actions(_exception), do: []
  end
end

defmodule PluteusWeb.GoneError do
  @moduledoc """
  Raised where a res was held and is not: recycled into the bin, or purged.

  The identifier stays refused rather than reused, so this is not a 404. What a person
  is shown is the deployment's error page for the status; the entity URI answers the
  same two states as a problem document, which is where a client reads the restore
  window from.
  """
  defexception [:message]

  defimpl Plug.Exception do
    def status(_exception), do: 410
    def actions(_exception), do: []
  end
end
