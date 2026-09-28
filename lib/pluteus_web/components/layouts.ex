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
  Puts a principal's contexts where the stylesheet is keyed and the first paint can
  already be right, rather than leaving the page to be corrected once a script runs.

  Two attributes per modifier where the intent is an outright choice, one where it is
  `system`. A.10.1 requires both the resolved value and the intent, and the server can
  resolve every intent but that one: `system` means a media feature decides, and a media
  feature is a fact about the browser.

  So a `system` intent renders `data-<modifier>-intent` and no `data-<modifier>`, which
  is what lets the generated stylesheet answer. Its fallbacks are scoped
  `:root:not([data-<modifier>])`, so the resolved attribute's absence is the condition
  they wait on, and rendering one would switch them off with nothing in their place.

  An outright intent renders both, including where it names the modifier's default
  context. That attribute matches no rule — the default is what `:root` already holds —
  and matching nothing is not the same as doing nothing: it is what takes the media
  query out of force. Choosing dark on a machine set to light is exactly that request,
  and dropping `data-theme="dark"` for being the default would let the machine overrule
  the person.

  `data-stored` names the modifiers the store answers for, so the script knows which
  ones it must not read out of shared storage. `data-declared` names the one the device
  declares, and both attributes are absent until it has, since §4.4 leaves an undeclared
  surface undetermined.
  """
  @spec context_attributes(%{String.t() => String.t()}, String.t() | nil) ::
          [{String.t(), String.t()}]
  def context_attributes(contexts, distance) do
    stored = contexts |> Map.keys() |> Enum.sort()

    intents =
      Enum.flat_map(stored, fn modifier ->
        intent = Map.fetch!(contexts, modifier)

        [{"data-#{modifier}-intent", intent} | resolved(modifier, intent)]
      end)

    named = if stored == [], do: [], else: [{"data-stored", Enum.join(stored, " ")}]

    named ++ intents ++ declaration(distance)
  end

  defp declaration(nil), do: []
  defp declaration(distance), do: [{"data-declared", "distance"}, {"data-distance", distance}]

  defp resolved(_modifier, "system"), do: []
  defp resolved(modifier, intent), do: [{"data-#{modifier}", intent}]

  @doc """
  Renders the controls for A.1.6's five context modifiers.

  Each is a radio group rather than a cycling button: a person choosing a context
  needs to see which one is in force and what the alternatives are, and a toggle that
  reveals its states only by being pressed does not say. A.9.4 keeps this out of a
  listbox, since every row is an action.

  The buttons write the resolved value and the intent onto the document root, which
  is where the generated stylesheet's scopes are keyed and where they survive a live
  navigation.

  A stored modifier's pressed state is rendered rather than scripted, so the control
  states the person's own choice in the first paint. A modifier the store does not hold
  has none to render and the script sets it once the document exists.
  """
  attr :contexts, :map,
    required: true,
    doc: "the intent each stored modifier carries, as `PluteusWeb.Contexts` assembles it"

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
            aria-pressed={to_string(Map.get(@contexts, modifier) == context)}
          >
            {context}
          </button>
        </div>
      </fieldset>
    </div>
    """
  end
end
