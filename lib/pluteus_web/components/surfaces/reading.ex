defmodule PluteusWeb.Surfaces.Reading do
  @moduledoc """
  How long-form text is set, and the controls a person sets it with
  ([ANNEX-A] A.3.6).

  Nine properties, each one a preference of the requesting principal's. spec-10 §14.5
  makes a text size confidential, and A.3.6 asks for the rest, so all nine are held in
  the preference store and none of them is a property of the holding being read.

  Every bound, every value and every step is the registry's, and `PluteusWeb.Settings`
  draws each one as the control its domain asks for. What this module settles is the CSS
  they become: a face is a family, a size is a proportion of long-form text's own step
  rather than a figure of its own, and a measure is the count of characters A.3.4 states
  a line in.

  The theme is the one property that cannot be a declaration on the text alone, because
  a theme moves the palette the whole page draws from. It is a region attribute, which
  the generated stylesheet carries a scope for; everything else is a declaration on the
  column the prose is set in.
  """

  use PluteusWeb, :html

  alias PluteusWeb.Settings

  @prefix "reading_"

  @doc """
  A.3.6's properties, in the order they are offered.
  """
  @spec keys() :: [String.t()]
  def keys, do: Settings.keys(:reading)

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

  Closed until it is asked for. These are set rarely and read from constantly, and a
  panel of nine controls standing over the text takes the room the text is for; a
  disclosure keeps every one of them one press away without spending the page on them.
  """
  attr :held, :map, required: true

  def preferences(assigns) do
    assigns = assigns |> assign(:keys, keys()) |> assign(:prefix, @prefix)

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
      </summary>

      <div class="grid gap-4 px-4 pb-4 sm:grid-cols-2 sm:px-6 lg:grid-cols-3">
        <Settings.control :for={key <- @keys} key={key} value={@held[key]} prefix={@prefix} />
      </div>
    </details>
    """
  end
end
