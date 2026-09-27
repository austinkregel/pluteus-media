defmodule Pluteus.Events.PlatformEvent do
  @moduledoc """
  What happened to the holdings: spec-01 §11.2's platform class.

  Acquired, placed, normalized, verified, matched, corrected. Most are the System
  principal's (spec-04 §3), and a household unable to see them could not see its
  own library changing, so every member reads all of them.

  `recorded_by` is who acted. §11.2 makes the class a question of what the event
  records rather than who acted, so a member correcting a name produces one of
  these and not a consumption event; spec-06 §6.4 requires that be visible, which
  is why the column is here.

  There is no principal-scoping column, and that absence is the point: criterion 42
  forbids a platform event to carry, or be combined into, what any principal
  consumed, and a table with nothing to scope by cannot be combined into it.

  **The subject is a res or an acquisition, exactly one.** §11.1 gives "a file
  arriving" as an event, and an arrival precedes anything catalogued, so `acquired`
  has no res to name; everything after placement does. The `one_subject` check is
  what keeps an event from being about both or about nothing.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Events.Registry

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "platform_events" do
    field :type, :string
    field :res_id, UUIDv7
    field :acquisition_id, UUIDv7
    field :recorded_by, UUIDv7
    field :occurred_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc """
  Builds a changeset for a platform event.

  A type the registry does not name in the platform class is refused. §11.3 leaves
  the vocabulary open to a deployment's own additions, and the registry is where
  they are added; what it does not name is a mistake rather than an addition.
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:id, :type, :res_id, :acquisition_id, :recorded_by, :occurred_at])
    |> validate_required([:type, :recorded_by, :occurred_at])
    |> validate_inclusion(:type, Registry.types(:platform),
      message: "is not a platform event type the registry names"
    )
    |> check_constraint(:res_id, name: :one_subject)
    |> foreign_key_constraint(:res_id)
    |> foreign_key_constraint(:acquisition_id)
    |> foreign_key_constraint(:recorded_by)
  end
end
