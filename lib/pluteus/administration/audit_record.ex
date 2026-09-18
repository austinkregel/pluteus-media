defmodule Pluteus.Administration.AuditRecord do
  @moduledoc """
  A privileged operation: who did it, to whom, what, when, and whether it
  worked (spec-06 §6.6).

  Written whether the operation succeeded or failed; an attempt that failed is
  as much a finding as one that worked. There is no field that could carry what
  anyone consumed — §6.6 lets an Administrator read these, and §6.3 forbids
  their showing consumption.
  """

  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "audit_records" do
    field :actor_id, UUIDv7
    field :subject_id, UUIDv7
    field :operation, :string
    field :outcome, Ecto.Enum, values: [:succeeded, :failed]
    field :reason, :string
    field :occurred_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
end
