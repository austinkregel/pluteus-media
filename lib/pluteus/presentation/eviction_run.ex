defmodule Pluteus.Presentation.EvictionRun do
  @moduledoc """
  One pass of the eviction policy, recorded as having run ([spec-10] §11.6).

  **The eviction must be observable as having run**, because a timer that silently
  fails fills a disk and the failure is invisible until it is total. A row is written
  when the pass starts and completed when it ends, so a pass that crashed halfway
  leaves `finished_at` null and is visible as an unfinished run rather than inferred
  from free space.

  The counts are on the completion rather than the start, since what a pass considered
  is not known until it has looked.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "presentation_evictions" do
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :considered, :integer
    field :evicted, :integer
    field :bytes_reclaimed, :integer

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def started_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:started_at])
    |> validate_required([:started_at])
  end

  def finished_changeset(run, attrs) do
    run
    |> cast(attrs, [:finished_at, :considered, :evicted, :bytes_reclaimed])
    |> validate_required([:finished_at, :considered, :evicted, :bytes_reclaimed])
    |> check_constraint(:finished_at, name: :a_finished_run_states_what_it_did)
  end
end
