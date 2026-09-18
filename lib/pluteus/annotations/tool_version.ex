defmodule Pluteus.Annotations.ToolVersion do
  @moduledoc """
  One build of one deriving tool.

  spec-02 §4.2 requires `version` to distinguish any two builds that could
  produce different numbers for the same input, which is why it is not a
  semantic version chosen by hand and why its string carries no order.
  `sequence` supplies the order: the order in which this system first recorded
  each build. "Newer" in supersession and "before version X" both mean it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "tool_versions" do
    field :tool, :string
    field :version, :string
    field :sequence, :integer, read_after_writes: true

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(tool_version, attrs) do
    tool_version
    |> cast(attrs, [:tool, :version])
    |> validate_required([:tool, :version])
    |> unique_constraint([:tool, :version])
  end
end
