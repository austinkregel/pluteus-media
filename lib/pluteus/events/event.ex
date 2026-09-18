defmodule Pluteus.Events.Event do
  @moduledoc """
  A descriptive record of something a principal did.

  §11.1 gives events no notion of current state, so questions of editability do
  not arise. Play count is a count over these; resume position is not, and lives
  in its own table because it is state rather than history.

  `type` is seed data (§11.3).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Res
  alias Pluteus.Principals.Principal

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "events" do
    belongs_to :principal, Principal, define_field: false
    belongs_to :res, Res, define_field: false

    field :principal_id, UUIDv7
    field :res_id, UUIDv7

    field :type, :string
    field :occurred_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:id, :principal_id, :res_id, :type, :occurred_at])
    |> validate_required([:principal_id, :res_id, :type, :occurred_at])
    |> foreign_key_constraint(:principal_id)
    |> foreign_key_constraint(:res_id)
  end
end
