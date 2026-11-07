defmodule Pluteus.Matching.SourceAgent do
  @moduledoc """
  The collective agent a source is (spec-05 §3.1), found again by the name the registry
  gives the source.
  """

  use Ecto.Schema

  @primary_key {:source, :string, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "source_agents" do
    field :agent_id, UUIDv7
  end

  @type t :: %__MODULE__{}
end
