defmodule Pluteus.Catalog.Profile do
  @moduledoc """
  The preferences resolution reads when choosing among the names a res carries.

  A nil `assigner_id` asks for the household's shared vocabulary, which §7.3
  makes the unmarked default and §7.4 the terminal fallback. A nil `language`
  expresses no language preference; it does not ask for names that are
  themselves untagged.
  """

  defstruct [:language, :assigner_id]

  @type t :: %__MODULE__{
          language: String.t() | nil,
          assigner_id: Ecto.UUID.t() | nil
        }
end
