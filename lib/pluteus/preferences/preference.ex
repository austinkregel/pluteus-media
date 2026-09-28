defmodule Pluteus.Preferences.Preference do
  @moduledoc """
  One preference a principal holds (spec-10 §14.5).

  §14.5 makes these that principal's and not another's: "A principal's caption
  styling, motion preference, contrast preference, text size and described-audio
  default are that principal's and MUST NOT be visible to another. They are not
  consumption data, but they disclose a disability as directly as a play history
  discloses a taste." §21 restates it — "per principal and are not
  household-visible".

  The key is half the primary key, so a principal holds each preference once and
  setting it again replaces it. A row exists only where a principal has set
  something: the registry holds the defaults, so an unset preference is an absent
  row rather than a row carrying a default, and nothing has to tell the two apart.

  The key's domain is the `preference_key_is_known` check in the database. The
  value's is the registry's, because it differs per key and one column cannot hold
  a domain per key — so `Pluteus.Preferences.Registry.admits?/2` is what refuses a
  value, and `changeset/2` is the only way in.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Preferences.Registry
  alias Pluteus.Principals.Principal

  @primary_key false
  @foreign_key_type UUIDv7
  schema "principal_preferences" do
    belongs_to :principal, Principal, primary_key: true, type: UUIDv7

    field :key, :string, primary_key: true
    field :value, :string

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc """
  A preference a principal sets.

  An unknown key is refused before its value is looked at, because a value's domain
  is the key's and there is none to check it against.
  """
  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [:principal_id, :key, :value])
    |> validate_required([:principal_id, :key, :value])
    |> validate_inclusion(:key, Registry.keys())
    |> validate_value()
    |> check_constraint(:key, name: :preference_key_is_known)
    |> unique_constraint([:principal_id, :key], name: :principal_preferences_pkey)
    |> foreign_key_constraint(:principal_id)
  end

  defp validate_value(changeset) do
    key = get_field(changeset, :key)
    value = get_field(changeset, :value)

    cond do
      changeset.errors != [] -> changeset
      is_nil(key) or is_nil(value) -> changeset
      Registry.admits?(key, value) -> changeset
      true -> add_error(changeset, :value, "is outside #{key}'s domain", domain: key)
    end
  end
end
