defmodule Pluteus.Principals.Principal do
  @moduledoc """
  An identity that uses the system.

  LRM's agent, person and collective agent describe entities referenced *by*
  content. A principal is a different thing: who is looking. §10.1 places it
  outside LRM, so a principal is not a res and cannot be named, credited, or
  made the subject of a work.

  `person_id` is the optional bridge between the two. The deployment itself acts
  as a principal and corresponds to no person, and a person who appears in
  household media and assigns names but holds no login is an agent and no
  principal. Both cases have to be representable, so the link is nullable and
  neither side implies the other.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Res

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "principals" do
    field :role, :string

    belongs_to :person, Res, define_field: false
    field :person_id, UUIDv7
    field :person_kind, Ecto.Enum, values: Res.kinds()
    field :retired_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @roles ~w(system administrator member guest)

  @doc """
  The roles spec-06 §6.1 defines. Their permissions are normative, so the set
  changes only with a release.
  """
  @spec roles() :: [String.t()]
  def roles, do: @roles

  def changeset(principal, attrs) do
    principal
    |> cast(attrs, [:id, :role, :person_id, :person_kind])
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
    |> check_constraint(:role, name: :role_must_be_known)
    |> unique_constraint(:role, name: :principals_one_system_index)
    |> check_constraint(:person_id, name: :person_link_is_whole)
    |> check_constraint(:person_kind, name: :principal_stands_for_a_person)
    |> unique_constraint(:person_id)
    |> foreign_key_constraint(:person_id)
  end
end
