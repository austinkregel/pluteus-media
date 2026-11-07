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
  alias PluteusWeb.Absence
  alias PluteusWeb.Surfaces.Medium

  attr :name, :string, required: true
  attr :category, :string, required: true
  attr :borne, :any, required: true
  attr :facts, :list, required: true

  attr :place, :map,
    required: true,
    doc: """
    Where the photograph was taken: each place of capture said by its names and those of
    the places containing it, whether a tool or a person put it there, and the decision
    that put it there where one can be undone; the field's state where no place is
    recorded; the finer places proposed and not yet decided; and the places the household
    has said it was not taken in.
    """

  def surface(assigns) do
    assigns = assign(assigns, :reserved, reserved(assigns.borne, assigns.category))

    ~H"""
    <div class="flex w-full flex-1 flex-col">
      <Medium.band name={@name} category={@category} />

      <div class="flex flex-1 flex-col gap-4 lg:flex-row">
        <div class="flex min-w-0 flex-1 items-start p-4 sm:p-6">
          <.picture name={@name} borne={@borne} reserved={@reserved} />
        </div>

        <.beside facts={@facts} place={@place} />
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
  attr :place, :map, required: true

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
      <dl class="flex flex-col gap-4">
        <div :for={{label, said} <- @facts} class="flex flex-col gap-1">
          <dt class="text-caption uppercase text-on-surface-muted">{label}</dt>
          <dd class="text-body-sm text-on-surface-strong">{said}</dd>
        </div>

        <div
          :for={captured <- @place.captured}
          id={"viewer-place-#{captured.place_id}"}
          class="flex flex-col gap-1"
        >
          <dt class="text-caption uppercase text-on-surface-muted">Taken in</dt>
          <dd class="text-body-sm text-on-surface-strong"><.names said={captured.said} /></dd>
          <dd class="text-caption text-on-surface-muted">{who_said(captured.provenance)}</dd>
          <dd>
            <.button
              :if={captured.provenance == :automatic}
              id={"viewer-wrong-place-#{captured.place_id}"}
              variant="bare"
              phx-click="reject-place"
              phx-value-place={captured.place_id}
            >
              Not here
            </.button>
            <.button
              :if={captured.undo}
              id={"viewer-undo-#{captured.undo}"}
              variant="bare"
              phx-click="reconsider-place"
              phx-value-candidate={captured.undo}
            >
              Undo
            </.button>
          </dd>
        </div>

        <div :if={@place.absent} id="viewer-place-absent" class="flex flex-col gap-1">
          <dt class="text-caption uppercase text-on-surface-muted">Taken in</dt>
          <dd class="text-body-sm"><Absence.statement state={@place.absent} /></dd>
        </div>
      </dl>

      <section
        :for={proposed <- @place.proposed}
        id={"viewer-proposed-place-#{proposed.candidate_id}"}
        aria-label={"Possibly taken in #{Enum.join(proposed.said, ", ")}"}
        class="flex flex-col gap-2"
      >
        <p class="text-body-sm text-on-surface-strong">
          Possibly taken in <.names said={proposed.said} />
        </p>
        <p class="text-caption text-on-surface-muted">
          The photograph's location is too coarse to say this for certain.
        </p>

        <div class="flex gap-2">
          <.button
            id={"viewer-taken-here-#{proposed.candidate_id}"}
            phx-click="decide-place"
            phx-value-candidate={proposed.candidate_id}
            phx-value-decision="taken-here"
          >
            Taken here
          </.button>
          <.button
            id={"viewer-not-here-#{proposed.candidate_id}"}
            variant="bare"
            phx-click="decide-place"
            phx-value-candidate={proposed.candidate_id}
            phx-value-decision="not-here"
          >
            Not here
          </.button>
        </div>
      </section>

      <section
        :for={declined <- @place.declined}
        id={"viewer-declined-place-#{declined.candidate_id}"}
        aria-label={"Not taken in #{Enum.join(declined.said, ", ")}"}
        class="flex flex-col gap-1"
      >
        <p class="text-body-sm text-on-surface-strong">
          Not taken in <.names said={declined.said} />
        </p>
        <p class="text-caption text-on-surface-muted">Said by the household</p>
        <div>
          <.button
            id={"viewer-undo-#{declined.candidate_id}"}
            variant="bare"
            phx-click="reconsider-place"
            phx-value-candidate={declined.candidate_id}
          >
            Undo
          </.button>
        </div>
      </section>
    </aside>
    """
  end

  # [spec-10] §7: each name takes its direction from itself, so a right-to-left name in a
  # list of left-to-right ones is not reordered with its neighbours.
  attr :said, :list, required: true

  defp names(assigns) do
    ~H"""
    <span :for={{name, index} <- Enum.with_index(@said)} phx-no-format><bdi>{name}</bdi>{if index < length(@said) - 1, do: ", "}</span>
    """
  end

  # [spec-10] §15.3: whether a tool or a person put the place there is visible beside it.
  defp who_said(:automatic), do: "Matched from the photograph's own location"
  defp who_said(:local), do: "Confirmed by the household"

  defp reserved(nil, category), do: Geometry.reserve(nil, category)

  defp reserved(borne, category) do
    Geometry.reserve(Geometry.for_res([borne])[borne], category)
  end
end
