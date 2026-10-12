defmodule PluteusWeb.Settings do
  @moduledoc """
  A preference as a control, drawn from the domain §20 gives its key.

  Every bound, every value and every step is the registry's: a control that offered a
  size the registry does not admit would be offering a setting nobody could hold, and
  one that chose its own increment would be settling how many settings there are.

  A named set is offered as a group of choices and a quantity as a slider, because a
  quantity's domain is a range and buttons over one would be a handful of values the
  registry never named. The slider carries its value in words beside it, since a number
  on a track says nothing about what it is a number of.

  What each surface offers is the surface's own — a reader offers how it reads and a
  player offers how a caption is drawn — and the key a control carries is the only thing
  the event needs, so one handler answers all of them.
  """

  use PluteusWeb, :html

  alias Pluteus.Preferences.Registry, as: Preferences

  # Face, then the three that decide how much of a line a person takes in at once, then
  # the two that space what is inside it, then how a line ends, then the theme. A person
  # changing the face wants the size next, and the leading and measure are what they
  # judge together.
  @reading ~w(reading_face reading_size reading_line_height reading_measure
              reading_letter_spacing reading_word_spacing reading_alignment
              reading_hyphenation reading_theme)

  # §17.4's caption presentation. The ground comes before the edge because the edge is
  # what compensates for removing the ground.
  @captions ~w(caption_face caption_size caption_ground caption_edge)

  @doc """
  The keys a surface offers, in the order it offers them.

  The set is the registry's: a key it carries under a group's prefix and this order
  omits raises, rather than being a preference a person holds and no surface offers.
  """
  @spec keys(:reading | :captions) :: [String.t()]
  def keys(:reading), do: offered("reading_", @reading)
  def keys(:captions), do: offered("caption_", @captions)

  @doc """
  Every key any surface may set, which is what an event is answered against.
  """
  @spec settable() :: [String.t()]
  def settable, do: keys(:reading) ++ keys(:captions) ++ ["subtitle_visibility"]

  defp offered(prefix, order) do
    case Enum.filter(Preferences.keys(), &String.starts_with?(&1, prefix)) -- order do
      [] ->
        order

      unoffered ->
        raise "the registry carries #{Enum.join(unoffered, ", ")}, which nothing offers"
    end
  end

  @doc """
  One preference, as the control its domain asks for.
  """
  attr :key, :string, required: true
  attr :value, :string, required: true
  attr :prefix, :string, default: ""

  def control(assigns) do
    assigns
    |> assign(:label, label(assigns.key, assigns.prefix))
    |> assign(:domain, Preferences.domain(assigns.key))
    |> drawn()
  end

  defp drawn(%{domain: %{"kind" => "one_of"}} = assigns) do
    ~H"""
    <fieldset class="flex flex-col gap-1">
      <legend class="text-caption text-on-surface-muted">{@label}</legend>
      <div class="flex flex-wrap gap-2">
        <button
          :for={value <- @domain["values"]}
          type="button"
          phx-click="prefer"
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

  defp drawn(%{domain: %{"kind" => "number"}} = assigns) do
    ~H"""
    <div class="flex flex-col gap-1">
      <label for={"preference-#{@key}"} class="text-caption text-on-surface-muted">
        {@label}
      </label>
      <form phx-change="prefer" class="flex items-center gap-3">
        <input type="hidden" name="key" value={@key} />
        <input
          type="range"
          id={"preference-#{@key}"}
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

  # The key, less the prefix that says which kind of thing it governs. The registry names
  # the properties and this is that name said in the household's words, so a property
  # added there is offered under its own name rather than one typed here.
  @doc """
  What a key is called where its group is already named.
  """
  @spec label(String.t(), String.t()) :: String.t()
  def label(key, prefix) do
    said = key |> String.replace_prefix(prefix, "") |> String.replace("_", " ")

    String.replace(said, ~r/^./, &String.upcase(&1))
  end

  defp said("interface"), do: "Follow"
  defp said("foreign_audio"), do: "Foreign audio"
  defp said(value), do: String.replace(value, ~r/^./, &String.upcase(&1))

  # A unit as a reader would say it rather than as the registry keys it, because the
  # figure is read out by a screen reader and `ratio` is not a word about lines.
  defp quantity(value, "percent"), do: "#{value} per cent"
  defp quantity(value, "characters"), do: "#{value} characters"
  defp quantity(value, "ratio"), do: "#{value} times the size"
  defp quantity(value, "em"), do: "#{value} em"
end
