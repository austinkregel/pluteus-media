defmodule PluteusWeb.CoreComponents do
  @moduledoc """
  The components every surface is built from, bound to spec-10 Annex A's `sys`
  vocabulary.

  A.1.4 confines a template to the `sys` tier, so every class here names a semantic
  role and never a ramp step: `bg-fill-subtle`, not `bg-grey-03`. The utilities exist
  because `mix design.build` registers each role in Tailwind's theme layer, and the
  primitives generate utilities too — that they exist is not permission to use them.

  A.9.5 governs how a variant is chosen. A variant set is enumerated, and an
  unmapped variant raises rather than resolving to a default, so a typo is an error
  at the call site instead of a control that renders in the wrong emphasis. Where a
  set can be checked at compile time it is, through `attr`'s `values`, which
  `warnings_as_errors` turns into a build failure.

  ## The emphasis ladder, and why no control is a coloured button

  A.11 fixes the emphasis vocabulary as `subtle` / bare / `strong` / `solid`, and
  A.2.6 spends saturation on the class and status colours alone — so emphasis is
  carried by the neutral ramp, weight and a boundary, and there is no brand-coloured
  primary action anywhere in the interface.

  What a solid fill is for is a measurement rather than a preference. Against
  `sys.color.on.fill` a solid rung reaches 4.27:1 in the dark theme and 4.96:1 in
  the light, and no step of the ramp reaches 4.5:1 on either — the midpoint of a
  neutral ramp is the worst case for both polarities. So a solid fill carries a
  glyph, a badge or a meter, and a control with a word in it is built from
  `fill.subtle`, where the surface's own ink reaches 13.71:1 and 14.41:1.

  ## What belongs here

  A component is one of A.9.3's inventory, and A.9.1 admits it only once its states
  are enumerated, its keyboard and directional-remote interactions are defined, and
  its populated, empty, error and loading renderings all exist. This module holds the
  form primitives and the notice, which is what a form and a flash need.
  """
  use Phoenix.Component

  import PluteusWeb.Icon, only: [icon: 1]

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  # A.4.3's component border, as the one width a control's edge is drawn at. The
  # `length:` hint is needed because Tailwind cannot tell a width from a colour when
  # the value is a variable. Functions rather than module attributes because inside a
  # HEEx template `@name` means an assign, so an attribute would silently render
  # nothing; the returned string is still a complete literal, which is what A.9.5
  # requires — a name assembled at run time produces no rule at all.
  defp edge, do: "border-[length:var(--sys-border-width-component)]"

  # A.4.2's pointer floor, the smallest a control may be on this surface. A remote
  # surface takes `min-h-target-remote`, which is why the floor is asked for by name
  # rather than written as a number each control remembers.
  defp target, do: "min-h-target-pointer"

  @doc """
  Renders a notice.

  A.9.3 makes a notice `role="status"` by default and reserves `role="alert"` for a
  playback failure, because an assertive live region interrupts a screen reader
  mid-sentence and almost nothing earns that.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of the notice container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "which status role the notice carries"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the notice container"

  slot :inner_block, doc: "the optional inner block that renders the notice's message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role={if @kind == :error, do: "alert", else: "status"}
      class="fixed top-4 right-4 z-50 w-80 max-w-[calc(100vw-2rem)] sm:w-96"
      {@rest}
    >
      <div class={[
        "flex items-start gap-3 rounded-lg p-4",
        "bg-surface-overlay text-on-surface-strong",
        edge(),
        @kind == :info && "border-border-component",
        @kind == :error && "border-status-error"
      ]}>
        <.icon
          name={
            if @kind == :error,
              do: "hero-exclamation-circle-mini",
              else: "hero-information-circle-mini"
          }
          class={["shrink-0", @kind == :error && "text-status-error"]}
        />
        <div class="grow text-body-sm">
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <button
          type="button"
          id={"#{@id}-close"}
          class="shrink-0 rounded-sm text-on-surface-muted hover:text-on-surface-strong"
          aria-label="close"
        >
          <.icon name="hero-x-mark-mini" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button, or a link styled as one.

  The variant is A.11's emphasis vocabulary. `bare` has no fill and no edge;
  `subtle` is the resting control; `strong` adds A.6's significant boundary and a
  heavier weight, which is how a primary action is distinguished where colour is
  spent elsewhere; `solid` is a field for a glyph and takes no label, since no ramp
  step reaches 4.5:1 on a solid fill in both themes.

  An unmapped variant raises, per A.9.5.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="strong">Send!</.button>
      <.button navigate={~p"/notices"}>Notices</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any, default: nil
  attr :variant, :string, default: "subtle", values: ~w(bare subtle strong solid)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "bare" => ["text-on-surface-strong hover:bg-fill-subtle"],
      "subtle" => [
        "bg-fill-subtle hover:bg-fill-subtle-strong text-on-surface-strong",
        edge(),
        "border-border-component hover:border-border-component-strong"
      ],
      "strong" => [
        "bg-fill-subtle hover:bg-fill-subtle-strong text-on-surface-strong font-semibold",
        edge(),
        "border-border-strong"
      ],
      "solid" => ["bg-fill-solid hover:bg-fill-solid-strong text-on-fill"]
    }

    assigns =
      assign(assigns, :class, [
        "inline-flex items-center justify-center gap-2 rounded-md px-4 text-body-sm",
        target(),
        "transition-colors duration-[var(--sys-motion-duration-state)] ease-standard",
        "disabled:opacity-50 disabled:pointer-events-none",
        Map.fetch!(variants, assigns.variant),
        assigns.class
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with its label and any error messages.

  A `Phoenix.HTML.FormField` may be passed as argument, which is used to retrieve
  the input name, id, and values. Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-4">
      <label for={@id} class={["flex items-center gap-3 text-body-sm", target()]}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={
            @class ||
              ["size-5 shrink-0 rounded-sm bg-fill-subtle", edge(), "border-border-component"]
          }
          {@rest}
        />
        <span class="text-on-surface-strong">{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-4">
      <.label for={@id} label={@label} />
      <select
        id={@id}
        name={@name}
        class={[
          @class || field_classes(),
          @errors != [] && (@error_class || "border-status-error")
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-4">
      <.label for={@id} label={@label} />
      <textarea
        id={@id}
        name={@name}
        class={[
          @class || field_classes(),
          "min-h-32 py-2",
          @errors != [] && (@error_class || "border-status-error")
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="mb-4">
      <.label for={@id} label={@label} />
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          @class || field_classes(),
          @errors != [] && (@error_class || "border-status-error")
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # An input is something a person operates, so it takes a fill rather than a
  # surface, and the ring comes from app.css's one `:focus-visible` rule rather than
  # from each field remembering it.
  defp field_classes do
    [
      "w-full rounded-md bg-fill-subtle px-3 text-body-md text-on-surface-strong",
      "placeholder:text-on-surface-muted",
      edge(),
      "border-border-component",
      target()
    ]
  end

  attr :for, :string, default: nil
  attr :label, :string, default: nil

  defp label(assigns) do
    ~H"""
    <label :if={@label} for={@for} class="mb-1 block text-body-sm text-on-surface-muted">
      {@label}
    </label>
    """
  end

  # A form error, in words, beside the field it belongs to.
  #
  # The words take the surface's own ink and the glyph takes the status colour. A.2.6
  # makes a status role "a solid with an `on` pair" and never a text colour, and the
  # measurement agrees: on a raised surface in the dark theme the error solid falls to
  # 4.07:1, under WCAG 2 §1.4.3's 4.5:1 for body text, and a form sits on a raised
  # surface. Colouring the message would also make colour the emphasis, where spec-10
  # §17.9 wants a carrier that is not colour — which here is the glyph and the sentence.
  defp error(assigns) do
    ~H"""
    <p class="mt-1 flex items-center gap-2 text-body-sm text-on-surface-strong">
      <.icon name="hero-exclamation-circle-mini" class="shrink-0 text-status-error" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with a title, an optional subtitle and optional actions.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-start justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-title-md font-semibold text-on-surface-strong">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-body-sm text-on-surface-muted">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div :if={@actions != []} class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="w-full text-left text-body-sm text-on-surface-strong">
      <thead class="text-on-surface-muted">
        <tr class="border-b border-border-subtle">
          <th :for={col <- @col} class="py-2 pr-4 font-medium">{col[:label]}</th>
          <th :if={@action != []} class="py-2">
            <span class="sr-only">Actions</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr
          :for={row <- @rows}
          id={@row_id && @row_id.(row)}
          class="border-b border-border-subtle last:border-0 hover:bg-fill-subtle"
        >
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={["py-2 pr-4", @row_click && "cursor-pointer"]}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 py-2">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list of titled values.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <dl class="divide-y divide-border-subtle">
      <div :for={item <- @item} class="flex flex-col gap-1 py-3 sm:flex-row sm:gap-4">
        <dt class="text-body-sm text-on-surface-muted sm:w-48 sm:shrink-0">{item.title}</dt>
        <dd class="text-body-md text-on-surface-strong">{render_slot(item)}</dd>
      </div>
    </dl>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-enter duration-200", "opacity-0 translate-y-2",
         "opacity-100 translate-y-0"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-exit duration-200", "opacity-100 translate-y-0",
         "opacity-0 translate-y-2"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # You can make use of gettext to translate error messages by
    # uncommenting and adjusting the following code:

    # if count = opts[:count] do
    #   Gettext.dngettext(PluteusWeb.Gettext, "errors", msg, msg, count, opts)
    # else
    #   Gettext.dgettext(PluteusWeb.Gettext, "errors", msg, opts)
    # end

    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
