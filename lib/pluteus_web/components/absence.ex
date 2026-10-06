defmodule PluteusWeb.Absence do
  @moduledoc """
  The words an absent value is said in, and the two ways a surface says them
  ([spec-10] §5.2, §5.3).

  §5.3: an absence is rendered "in the place the value would have gone, in words, as an
  assertion" — never a dash, a blank cell, a zero, an epoch date or a synthesised value,
  and never conveyed by emptiness, because an empty cell is indistinguishable from a cell
  that failed to render.

  One module holds the words because §5.2's own point is that the states are different
  facts and an interface that renders them alike tells the household something false. Two
  surfaces wording one state differently would be the same failure arriving by a longer
  route: a reader cannot learn a vocabulary that changes per page.

  A state with no words raises rather than rendering as nothing. A.8.8 makes that an
  invariant rather than a convention — the state may never be left unset — and
  `Pluteus.Representation.Field` is where the set of states is fixed, so a state added
  there and not worded here fails loudly the first time a surface meets it.
  """
  use PluteusWeb, :html

  # §5.2's seven absences. *Held* is not among them: it is the value being there, and
  # A.8.8 gives it no marker for the same reason.
  @words %{
    "not_held" => "not held",
    "not_yet_examined" => "not yet examined",
    "attempted_failed" => "a tool tried and could not establish this",
    "unknown" => "unknown — a source was consulted and stated none",
    "sought_not_found" => "looked for and not found",
    "known_unknowable" => "known to be unrecoverable",
    "known_absent" => "known to be absent"
  }

  @doc """
  The words a state is said in.

  Raises where a state has none, which is what makes an unworded state a loud failure
  rather than a surface that renders nothing in the value's place.
  """
  @spec words(String.t()) :: String.t()
  def words(state), do: Map.fetch!(@words, state)

  @doc """
  Every state these words cover.
  """
  @spec states() :: [String.t()]
  def states, do: @words |> Map.keys() |> Enum.sort()

  @doc """
  An absence, in words, in the place the value would have gone.

  Muted rather than hidden: it is the value's own place and it reaches assistive
  technology as content, which §5.3 requires of it.
  """
  attr :state, :string, required: true
  attr :class, :any, default: nil

  def statement(assigns) do
    ~H"""
    <span class={["text-on-surface-muted", @class]}>{words(@state)}</span>
    """
  end

  @doc """
  A field as the wire carries it: its value where it is held, its absence in words where
  it is not.

  The held value is the caller's to render, because formatting one is a property of what
  the field holds rather than of absence. The slot is only reached where the state is
  held, so a caller may format a value without guarding for its absence.

  ## Examples

      <Absence.field field={@field}>{said(@field["value"])}</Absence.field>
  """
  attr :field, :map, required: true
  slot :inner_block, required: true

  def field(assigns) do
    ~H"""
    <span :if={@field["state"] == "held"}>{render_slot(@inner_block)}</span>
    <.statement :if={@field["state"] != "held"} state={@field["state"]} />
    """
  end
end
