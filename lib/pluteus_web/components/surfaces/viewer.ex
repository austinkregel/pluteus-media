defmodule PluteusWeb.Surfaces.Viewer do
  @moduledoc """
  The viewer: the surface one photograph is looked at on ([spec-10] §12.1).

  The picture takes the page and its facts sit beside it. §11.2's box is reserved at the
  ratio the bytes were measured at, so the page does not move under a person while the
  image arrives.

  The image is asked for by profile at the manifestation's own address (§11.1), which is
  why the surface holds a manifestation rather than bytes.
  """

  use PluteusWeb, :html

  alias Pluteus.Presentation.Geometry
  alias Pluteus.Presentation.Registry, as: Presentation
  alias PluteusWeb.Surfaces.Medium

  attr :name, :string, required: true
  attr :category, :string, required: true
  attr :borne, :any, required: true
  attr :facts, :list, required: true

  def surface(assigns) do
    assigns = assign(assigns, :reserved, reserved(assigns.borne, assigns.category))

    ~H"""
    <div class="flex w-full flex-1 flex-col">
      <Medium.band name={@name} category={@category} />

      <div class="flex flex-1 flex-col gap-4 lg:flex-row">
        <div class="flex min-w-0 flex-1 items-start p-4 sm:p-6">
          <.picture name={@name} borne={@borne} reserved={@reserved} />
        </div>

        <.beside facts={@facts} />
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :borne, :any, required: true
  attr :reserved, :any, required: true

  defp picture(%{borne: nil} = assigns) do
    ~H"""
    <div
      id="viewer-absent"
      class={[
        "flex w-full items-center justify-center rounded-md p-10",
        "border-[length:var(--sys-border-width-component)] border-border-strong",
        "bg-surface-raised"
      ]}
      style={@reserved && "aspect-ratio: #{@reserved}"}
    >
      <p class="text-body-md text-on-surface-muted">No file is held for this.</p>
    </div>
    """
  end

  defp picture(assigns) do
    ~H"""
    <div
      id="viewer-picture"
      class={[
        "w-full overflow-hidden rounded-md",
        "border-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-base"
      ]}
      style={@reserved && "aspect-ratio: #{@reserved}"}
    >
      <img
        id="viewer-image"
        src={~p"/manifestations/#{@borne}/presentation/image-2048"}
        srcset={srcset(@borne)}
        sizes="(min-width: 1024px) 70vw, 100vw"
        alt={@name}
        class="size-full object-contain"
      />
    </div>
    """
  end

  # Every graded width §20 holds, so a browser takes the one its own pixels and density
  # ask for rather than the largest there is.
  defp srcset(borne) do
    Enum.map_join(Presentation.image_profiles(), ", ", fn profile ->
      "#{~p"/manifestations/#{borne}/presentation/#{profile["name"]}"} #{profile["width"]}w"
    end)
  end

  attr :facts, :list, required: true

  defp beside(assigns) do
    ~H"""
    <aside
      id="viewer-facts"
      aria-label="What is recorded about this"
      class={[
        "flex w-full shrink-0 flex-col gap-4 p-4 lg:w-88",
        "border-l-[length:var(--sys-border-width-hairline)] border-border-subtle"
      ]}
    >
      <dl :if={@facts != []} class="flex flex-col gap-4">
        <div :for={{label, said} <- @facts} class="flex flex-col gap-1">
          <dt class="text-caption uppercase tracking-wide text-on-surface-muted">{label}</dt>
          <dd class="text-body-sm text-on-surface-strong">{said}</dd>
        </div>
      </dl>

      <p :if={@facts == []} class="text-body-sm text-on-surface-muted">
        Nothing is recorded about this yet.
      </p>
    </aside>
    """
  end

  defp reserved(nil, category), do: Geometry.reserve(nil, category)

  defp reserved(borne, category) do
    Geometry.reserve(Geometry.for_res([borne])[borne], category)
  end
end
