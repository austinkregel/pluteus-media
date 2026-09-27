defmodule Mix.Tasks.Design.Build do
  @shortdoc "Generates the interface stylesheet from the design token file"

  @moduledoc """
  Writes `assets/css/tokens.css` from `priv/design`, in Annex A.10.1's three layers.

  It runs ahead of `tailwind` in `assets.build`, because the stylesheet it writes is
  what Tailwind's input imports. Under `assets/css/` rather than `priv/` so that
  Tailwind's own watcher sees it change: with that, editing a value in
  `priv/design/tokens.json` and running this task is enough for the browser to
  reload, since live reload already watches the CSS Tailwind emits.

  Changing a *context* needs none of this. A.10.1's layers put every semantic value
  on the document root, so switching `data-density="compact"` reassigns the whole
  spacing scale with no rebuild at all.

      docker compose run --rm app mix design.build
  """

  use Mix.Task

  alias Pluteus.Design.Build

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")

    written = Build.write!()
    Mix.shell().info("Wrote #{Path.relative_to_cwd(written)}")
  end
end
