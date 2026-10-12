defmodule PluteusWeb.Surfaces.Reading do
  @moduledoc """
  How long-form text is set, and the controls a person sets it with
  ([ANNEX-A] A.3.6).

  Nine properties, each one a preference of the requesting principal's. spec-10 §14.5
  makes a text size confidential, and A.3.6 asks for the rest, so all nine are held in
  the preference store and none of them is a property of the holding being read.

  Every bound, every value and every step is the registry's. What this module settles is
  the order they are offered in and the CSS each one becomes: a face is a family, a size
  is a proportion of long-form text's own step rather than a figure of its own, and a
  measure is the count of characters A.3.4 states a line in.

  The theme is the one property that cannot be a declaration on the text alone, because
  a theme moves the palette the whole page draws from. It is a region attribute, which
  the generated stylesheet carries a scope for; everything else is a declaration on the
  column the prose is set in.
  """

  use PluteusWeb, :html

  alias Pluteus.Preferences.Registry, as: Preferences

  @prefix "reading_"

  # Face, then the three that decide how much of a line a person takes in at once, then
  # the two that space what is inside it, then how a line ends, then the theme. A person
  # changing the face wants the size next, and the leading and measure are what they
  # judge together.
  @order ~w(reading_face reading_size reading_line_height reading_measure
            reading_letter_spacing reading_word_spacing reading_alignment
            reading_hyphenation reading_theme)

  @doc """
  A.3.6's properties, in the order they are offered.

  The set is the registry's. A key it carries and this order omits raises, rather than
  being a preference a person holds and no surface offers.
  """
  @spec keys() :: [String.t()]
  def keys do
    case Enum.filter(Preferences.keys(), &String.starts_with?(&1, @prefix)) -- @order do
      [] ->
        @order

      unoffered ->
        raise "the registry carries #{Enum.join(unoffered, ", ")}, which nothing offers"
    end
  end

  @doc """
  The declarations long-form text is set with, from the preferences a principal holds.

  A face and a theme are named rather than measured, so each is matched against the
  registry's own values and an unrecognised one raises: a value the domain does not
  carry has reached the store, and a column of unstyled text would not say so.
  """
  @spec prose_style(%{String.t() => String.t()}) :: String.t()
  def prose_style(held) do
    Enum.map_join(
      [
        {"font-family", "var(--font-#{family(held["reading_face"])})"},
        {"font-size", "calc(var(--sys-type-reading) * #{proportion(held["reading_size"])})"},
        {"line-height", held["reading_line_height"]},
        {"max-width", "#{held["reading_measure"]}ch"},
        {"letter-spacing", "#{held["reading_letter_spacing"]}em"},
        {"word-spacing", "#{held["reading_word_spacing"]}em"},
        {"text-align", alignment(held["reading_alignment"])},
        {"hyphens", hyphens(held["reading_hyphenation"])}
      ],
      " ",
      fn {property, value} -> "#{property}: #{value};" end
    )
  end

  @doc """
  The theme the text is read in, or nil where it follows the interface.
  """
  @spec theme(%{String.t() => String.t()}) :: String.t() | nil
  def theme(held), do: reading_theme(held["reading_theme"])

  defp reading_theme("interface"), do: nil
  defp reading_theme("dark"), do: "dark"
  defp reading_theme("light"), do: "light"

  defp family("sans"), do: "sans"
  defp family("serif"), do: "serif"
  defp family("mono"), do: "mono"

  defp alignment("start"), do: "start"
  defp alignment("justify"), do: "justify"

  defp hyphens("on"), do: "auto"
  defp hyphens("off"), do: "none"

  # A percentage as a multiplier, so the size follows a root the browser's own font
  # setting already moved rather than replacing it (A.1.3).
  defp proportion(percent) do
    {number, ""} = Float.parse(percent)

    "#{number / 100}"
  end

  @doc """
  The nine controls, each bound to the domain the registry gives its key.

  A named set is offered as a group of choices and a quantity as a slider, because a
  quantity's domain is a range and buttons over one would be a handful of values the
  registry never named. The slider carries its own value in words, since a number on a
  track says nothing about what it is a number of.

  Closed until it is asked for. These are set rarely and read from constantly, and a
  panel of nine controls standing over the text takes the room the text is for; a
  disclosure keeps every one of them one press away without spending the page on them.
  """
  attr :held, :map, required: true
  attr :principal_name, :any, required: true

  def preferences(assigns) do
    assigns = assign(assigns, :keys, keys())

    ~H"""
    <details
      id="reading-preferences"
      class={[
        "shrink-0",
        "border-b-[length:var(--sys-border-width-hairline)] border-border-subtle"
      ]}
    >
      <summary class={[
        "min-h-target-touch flex cursor-pointer items-center gap-3 px-4 sm:px-6",
        "text-body-md text-on-surface-muted hover:bg-fill-subtle-strong",
        "list-none [&::-webkit-details-marker]:hidden"
      ]}>
        <.icon name="hero-bars-3-mini" />
        <span>Reading preferences</span>
        <span class="grow"></span>
        <span class="text-caption">{kept_for(@principal_name)}</span>
      </summary>

      <div class="grid gap-4 px-4 pb-4 sm:grid-cols-2 sm:px-6 lg:grid-cols-3">
        <.control :for={key <- @keys} key={key} value={@held[key]} />
      </div>
    </details>
    """
  end

  # §14.5 makes these the principal's own and not the household's, which a person
  # setting one has to be able to see. A principal whose name nobody has recorded is
  # still the only one they are kept for.
  defp kept_for(nil), do: "Kept for you alone"
  defp kept_for(%{nomen_string: name}), do: "Kept for #{name} alone"

  attr :key, :string, required: true
  attr :value, :string, required: true

  defp control(assigns) do
    assigns
    |> assign(:label, label(assigns.key))
    |> assign(:domain, Preferences.domain(assigns.key))
    |> offered()
  end

  defp offered(%{domain: %{"kind" => "one_of"}} = assigns) do
    ~H"""
    <fieldset class="flex flex-col gap-1">
      <legend class="text-caption text-on-surface-muted">{@label}</legend>
      <div class="flex flex-wrap gap-2">
        <button
          :for={value <- @domain["values"]}
          type="button"
          phx-click="read-as"
          phx-value-key={@key}
          phx-value-value={value}
          aria-pressed={to_string(@value == value)}
          class={[
            "min-h-target-touch rounded-md px-3 text-body-sm",
            "border-[length:var(--sys-border-width-component)] border-border-strong",
            "bg-fill-subtle text-on-surface-muted hover:bg-fill-subtle-strong",
            "aria-pressed:bg-surface-overlay aria-pressed:font-medium",
            "aria-pressed:text-on-surface-strong"
          ]}
        >
          {said(value)}
        </button>
      </div>
    </fieldset>
    """
  end

  defp offered(%{domain: %{"kind" => "number"}} = assigns) do
    ~H"""
    <div class="flex flex-col gap-1">
      <label for={"reading-#{@key}"} class="text-caption text-on-surface-muted">
        {@label}
      </label>
      <form phx-change="read-as" class="flex items-center gap-3">
        <input type="hidden" name="key" value={@key} />
        <input
          type="range"
          id={"reading-#{@key}"}
          name="value"
          min={@domain["minimum"]}
          max={@domain["maximum"]}
          step={Preferences.step(@key)}
          value={@value}
          phx-debounce="200"
          aria-valuetext={quantity(@value, @domain["unit"])}
          class="grow accent-fill-solid"
        />
        <span class="w-20 shrink-0 text-right font-mono text-caption text-on-surface-muted">
          {quantity(@value, @domain["unit"])}
        </span>
      </form>
    </div>
    """
  end

  # The key, less the prefix that says which kind of text it governs. The registry names
  # the properties and this is that name said in the household's words, so a property
  # added there is offered under its own name rather than one typed here.
  defp label(key) do
    said = key |> String.replace_prefix(@prefix, "") |> String.replace("_", " ")

    String.replace(said, ~r/^./, &String.upcase(&1))
  end

  defp said("interface"), do: "Follow"
  defp said(value), do: String.replace(value, ~r/^./, &String.upcase(&1))

  # A unit as a reader would say it rather than as the registry keys it, because the
  # figure is read out by a screen reader and `ratio` is not a word about lines.
  defp quantity(value, "percent"), do: "#{value} per cent"
  defp quantity(value, "characters"), do: "#{value} characters"
  defp quantity(value, "ratio"), do: "#{value} times the size"
  defp quantity(value, "em"), do: "#{value} em"
end
