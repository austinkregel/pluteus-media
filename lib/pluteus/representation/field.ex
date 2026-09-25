defmodule Pluteus.Representation.Field do
  @moduledoc """
  One field of a representation: a value, and the state that value is in
  (spec-07 §4.1, spec-10 §5.2).

      "taken_at":     %{"state" => "held", "value" => "2009-07-14T16:12:00Z"}
      "photographer": %{"state" => "sought_not_found"}
      "loudness":     %{"state" => "not_yet_examined"}

  **A field is never carried by its omission.** A client receiving no field cannot
  tell a value nobody has looked for from one a tool failed on from one this
  deployment does not implement, and will render one as another.

  A state that is not `held` carries no `value` key at all, rather than a null:
  spec-10 §5.3 forbids rendering an absence as a default, a zero, an epoch date or
  an empty string, and a null on the wire invites exactly that.

  The term is the map the JSON encoder emits, so there is nothing to encode later.
  """

  @states ~w(
    held
    not_held
    not_yet_examined
    attempted_failed
    sought_not_found
    known_unknowable
    known_absent
  )a

  @absent @states -- [:held]

  @doc """
  spec-10 §5.2's seven states. A surface MUST distinguish all of them.
  """
  @spec states() :: [atom()]
  def states, do: @states

  @doc """
  The six a field carries where it holds no value.
  """
  @spec absent_states() :: [atom()]
  def absent_states, do: @absent

  @doc """
  A field holding a value.
  """
  @spec held(term()) :: map()
  def held(value), do: %{"state" => "held", "value" => value}

  @doc """
  A field holding none, in the state that establishes why.

  A state outside the six raises rather than reaching the wire: a client that
  received one it did not know would have no way to tell it from a field this
  deployment does not implement.
  """
  @spec absent(atom()) :: map()
  def absent(state) when state in @absent, do: %{"state" => to_string(state)}

  @doc """
  A field from a value and the state to report where there is none.

  An empty list is an absence, not a value: spec-10 §5.3 forbids an empty value
  that reads as a value, and "this work has no creators recorded" is a different
  statement from "this work has creators, and here are none of them".
  """
  @spec of(term(), atom()) :: map()
  def of(nil, state), do: absent(state)
  def of([], state), do: absent(state)
  def of(value, _state), do: held(value)
end
