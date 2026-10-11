defmodule PluteusWeb.Surfaces.Player do
  @moduledoc """
  The player: the surface a film, a television episode and a home video are presented on
  ([spec-10] §12.1).

  The picture is the page. The transport under it is the one §12.3 specifies and the
  chrome's own player keeps the queue, so what this adds to a holding already playable
  is the thing a transport cannot carry — a box with a picture in it, at the ratio the
  medium was recorded at.

  ## Why a box is reserved before the bytes arrive

  §11.2 requires a surface reserve a box of the ratio §20 names for the category where
  the probe has not run, rather than collapsing to zero and growing when the first frame
  decodes. A page that reflows as its medium loads moves what a person was reaching for.
  """

  use PluteusWeb, :html

  alias Pluteus.Playback
  alias Pluteus.Presentation.Geometry
  alias Pluteus.Surfaces.Registry, as: Surfaces

  attr :work, :map, required: true
  attr :name, :string, required: true
  attr :category, :string, required: true
  attr :playable, :any, required: true

  def surface(assigns) do
    assigns = assign(assigns, :reserved, reserved(assigns.playable, assigns.category))

    ~H"""
    <div class="mx-auto flex w-full max-w-7xl flex-1 flex-col gap-4 px-4 py-6 sm:px-6">
      <header class="flex shrink-0 items-baseline gap-3">
        <h1 class="text-title-lg font-medium text-on-surface-strong">{@name}</h1>
        <span class="text-body-sm text-on-surface-muted">
          {Surfaces.category_icon(@category).name}
        </span>
      </header>

      <.picture playable={@playable} reserved={@reserved} name={@name} />
    </div>
    """
  end

  attr :playable, :any, required: true
  attr :reserved, :any, required: true
  attr :name, :string, required: true

  defp picture(%{playable: {:error, _refusal}} = assigns) do
    ~H"""
    <div
      id="player-refusal"
      class={[
        "flex items-center justify-center rounded-md p-10",
        "border-[length:var(--sys-border-width-component)] border-border-strong",
        "bg-surface-raised"
      ]}
      style={box(@reserved)}
    >
      <p class="max-w-measure text-body-md text-on-surface-muted">
        {Playback.why(elem(@playable, 1))}
      </p>
    </div>
    """
  end

  defp picture(%{playable: {:ok, _ready}} = assigns) do
    ~H"""
    <div
      id="player-picture"
      class={[
        "relative w-full overflow-hidden rounded-md",
        "border-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-base"
      ]}
      style={box(@reserved)}
    >
      <video
        id="player-medium"
        controls
        preload="metadata"
        aria-label={@name}
        class="size-full"
        src={~p"/assets/#{first_part(@playable).asset_id}/content"}
      >
      </video>
    </div>
    """
  end

  # §11.2's reserved box: the ratio the bytes were measured at, and §20's assumed one
  # for the category where nothing has probed them. The holding is what carries the
  # geometry, since that is what the probe ran against.
  defp reserved({:ok, %{parts: [part | _rest]}}, category) do
    Geometry.reserve(Geometry.for_res([part.asset_id])[part.asset_id], category)
  end

  defp reserved({:error, _refusal}, category) do
    Geometry.reserve(nil, category)
  end

  # A category §20 reserves nothing for leaves the box to the medium, which is the one
  # case §11.2 does not reach: there is no ratio to be wrong about.
  defp box(nil), do: nil
  defp box(ratio), do: "aspect-ratio: #{ratio}"

  defp first_part({:ok, %{parts: [part | _rest]}}), do: part
end
