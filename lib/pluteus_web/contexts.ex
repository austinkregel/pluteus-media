defmodule PluteusWeb.Contexts do
  @moduledoc """
  The context modifiers a principal has chosen, for the document root to carry.

  Annex A.1.6 declares five modifiers and A.10.1 requires the resolved value and the
  person's intent both be recorded, "so that 'follow the system' is a third state
  rather than a lost one". What is assembled here is the intent, which is what the
  store holds; the resolved value follows from it, and for a modifier with a system
  signal only the browser can resolve it.

  Four of the five are the principal's. `distance` is not: spec-10 §4.4 records it
  "with the device", and A.10.3 makes it follow from that declaration rather than from
  anything a person carries between screens. Which four is not written here — a
  modifier is stored where the preference registry names a key after it, so the
  controls and the store cannot come to disagree about what is settable.

  With no principal this answers nothing, and the layout renders no attribute. That
  is what leaves `localStorage` in charge of a household-public page, and it is the
  only state in which `localStorage` decides anything: spec-10 §14.5 makes a stored
  preference confidential, and a shared browser's storage is the opposite of that.
  """

  @behaviour Plug

  import Plug.Conn

  alias Pluteus.Preferences
  alias Pluteus.Preferences.Registry
  alias Pluteus.Principals.Principal
  alias PluteusWeb.Layouts

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts), do: assign(conn, :contexts, held_by(conn.assigns.principal))

  @doc """
  The intent a principal holds for each stored modifier.
  """
  @spec held_by(Principal.t() | nil) :: %{String.t() => String.t()}
  def held_by(nil), do: %{}

  def held_by(%Principal{id: id}) do
    held = Preferences.held_by(id)

    Map.new(stored(), &{&1, Map.fetch!(held, &1)})
  end

  @doc """
  A.1.6's modifiers the preference store holds an intent for.
  """
  @spec stored() :: [String.t()]
  def stored do
    keys = Registry.keys()

    for {modifier, _contexts} <- Layouts.modifiers(), modifier in keys, do: modifier
  end
end
