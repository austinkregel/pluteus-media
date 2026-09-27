defmodule PluteusWeb.Layouts do
  @moduledoc """
  Layout components wrapping every rendered page.

  `root.html.heex` carries the HTML document shell and is rendered once per
  request, outside the LiveView lifecycle, so its contents do not re-render on
  live updates. A.10.1 requires the context attributes live on the document root
  for the same reason: they sit outside the region the server patches, so they
  survive navigation.
  """
  use PluteusWeb, :html

  embed_templates "layouts/*"

  @doc """
  Shows the notice group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of the notice container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path-micro" class="ml-1 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path-micro" class="ml-1 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  The five context modifiers A.1.6 declares, and the contexts each admits.

  The order is the resolver's `resolutionOrder`, which puts theme before contrast so
  that `more` picks a further step of whichever ramp theme chose.

  `system` is offered only where a system signal exists to follow. There is no media
  feature for how far away a person is sitting or how tightly they want things
  packed, so density and distance are chosen outright — which is also why the
  stylesheet emits a media query for three of the five and not all of them.
  """
  @spec modifiers() :: [{String.t(), [String.t()]}]
  def modifiers do
    [
      {"theme", ~w(system dark light)},
      {"contrast", ~w(system normal more)},
      {"motion", ~w(system full reduced)},
      {"density", ~w(comfortable compact)},
      {"distance", ~w(near far)}
    ]
  end

  @doc """
  Renders the controls for A.1.6's five context modifiers.

  Each is a radio group rather than a cycling button: a person choosing a context
  needs to see which one is in force and what the alternatives are, and a toggle that
  reveals its states only by being pressed does not say. A.9.4 keeps this out of a
  listbox, since every row is an action.

  The buttons write the resolved value and the intent onto the document root, which
  is where the generated stylesheet's scopes are keyed and where they survive a live
  navigation.
  """
  def context_controls(assigns) do
    assigns = assign(assigns, :modifiers, modifiers())

    ~H"""
    <div class="flex flex-col gap-4">
      <fieldset :for={{modifier, contexts} <- @modifiers} class="flex flex-wrap items-center gap-3">
        <legend class="sr-only">{modifier}</legend>
        <span class="w-20 shrink-0 text-body-sm text-on-surface-muted">{modifier}</span>
        <div class="flex flex-wrap gap-2" role="group" aria-label={modifier}>
          <button
            :for={context <- contexts}
            type="button"
            class={[
              "rounded-full px-3 text-body-sm min-h-target-pointer",
              "border-[length:var(--sys-border-width-component)]",
              "bg-fill-subtle hover:bg-fill-subtle-strong text-on-surface-strong",
              "border-border-component hover:border-border-component-strong",
              "aria-pressed:border-border-strong aria-pressed:font-semibold",
              "transition-colors duration-[var(--sys-motion-duration-state)] ease-standard"
            ]}
            data-modifier={modifier}
            data-context={context}
            aria-pressed="false"
          >
            {context}
          </button>
        </div>
      </fieldset>
    </div>
    """
  end
end
