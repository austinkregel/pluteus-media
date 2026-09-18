defmodule Pluteus.Catalog.Reconstruction do
  @moduledoc """
  The evidence that a recompression reproduces the original it replaced
  (spec-03 §4.3): the digest of bytes reconstructed from the recompression,
  computed here and found equal to the original's.

  It references res rather than assets. The original's asset row is purged when
  its window closes, and this record is what shows the discard was earned.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "reconstructions" do
    field :original_id, UUIDv7
    field :recompression_id, UUIDv7
    field :digest, :string
    field :digest_algorithm, :string
    field :verified_by, UUIDv7
    field :verified_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(reconstruction, attrs) do
    reconstruction
    |> cast(attrs, [
      :original_id,
      :recompression_id,
      :digest,
      :digest_algorithm,
      :verified_by,
      :verified_at
    ])
    |> validate_required([
      :original_id,
      :recompression_id,
      :digest,
      :digest_algorithm,
      :verified_by,
      :verified_at
    ])
    |> foreign_key_constraint(:original_id)
    |> foreign_key_constraint(:recompression_id)
    |> foreign_key_constraint(:verified_by)
  end
end
