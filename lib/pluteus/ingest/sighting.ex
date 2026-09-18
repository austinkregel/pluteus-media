defmodule Pluteus.Ingest.Sighting do
  @moduledoc """
  What the inbox last looked like for one file not yet acquired (spec-04 §4.1).

  A file is settled once the same size and modification time have been seen for
  the settle interval. Both are compared because a copy that preserves
  modification times still grows, and a rewrite in place can keep its size.
  """

  use Ecto.Schema

  @primary_key {:inbox_path, :string, autogenerate: false}
  schema "inbox_sightings" do
    field :size, :integer
    field :mtime, :integer
    field :seen_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{}
end
