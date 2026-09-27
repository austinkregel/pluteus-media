defmodule Pluteus.Principals.DeviceCredential do
  @moduledoc """
  What a principal holds on a device, and what it lets that device do
  (spec-06 §4.1, §4.2).

  §4.1 permits a device to hold a credential for more than one principal, each
  separately revocable: revoking one leaves the others, and no credential is
  reachable by the principal of another. The key is the pair, so that is what
  "separately" means here — a row per principal per device, which is also the unit
  [spec-10] criterion 55 requires be revocable.

  §4.1 states the cost rather than concealing it: a device holding several
  credentials is an ambient session for the people enrolled on it. A deployment
  may instead hold one at a time and re-run enrolment on a switch, which is slower
  and honest; which it does is a deployment decision that spec-10 §18.3 records.

  `key_digest` is the client key's digest and nothing else (spec-07 §3.2): the key
  is shown once at minting and never stored. A credential bound some other way,
  such as the device authorization grant, holds none.

  `granted` is §4.2's recorded grant, "a subset of the principal's role (§6.1)",
  which "MUST NOT be widened by the principal's role changing afterwards". Four
  things hold that, none of them a check a caller could forget: the column is NOT
  NULL with no default, so there is no state meaning *ask the role*;
  `Pluteus.Authorization.granted?/2` takes no principal, so no code path could
  consult a role to answer; `revocation_changeset/2` is the only update and does
  not cast it; and a trigger refuses to change it. The set of names it may hold
  excludes administration and identity mapping outright, so §4.2's prohibition on
  granting those is the column's domain rather than a rule anyone applies.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Principals.Device
  alias Pluteus.Principals.Principal

  # spec-07 §3.4, spec-06 §4.2 and spec-10 §18.3 state one grant in the same
  # words: reading the catalog, streaming, and writing its own principal's
  # consumption. `own_consumption` covers reading it as well as writing it,
  # following §6.1's Member row, which is one clause — a television must read its
  # own resume position to offer continuing, and a name covering only the write
  # would leave that unclassifiable.
  #
  # The vocabulary lives here because it is this column's domain, which the
  # `grant_is_grantable` check states in the database. Administration and identity
  # mapping are absent from it, so §4.2's prohibition on granting them is that
  # domain rather than a rule anyone applies.
  @grants ~w(read_catalog stream own_consumption)a

  @primary_key false
  @foreign_key_type UUIDv7
  schema "device_credentials" do
    belongs_to :device, Device, primary_key: true, type: UUIDv7
    belongs_to :principal, Principal, primary_key: true, type: UUIDv7

    field :key_digest, :string
    field :granted, {:array, Ecto.Enum}, values: @grants
    field :bound_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :revoked_by, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc """
  Every operation a recorded grant may name.
  """
  @spec grantable() :: [atom()]
  def grantable, do: @grants

  @doc """
  A credential a principal takes on a device.

  `granted` has no default: §4.2 makes a recorded grant a property of every
  credential, so a caller meaning "everything this role permits" says so with
  `Pluteus.Authorization.grantable_to/1`.
  """
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:device_id, :principal_id, :key_digest, :granted, :bound_at])
    |> validate_required([:device_id, :principal_id, :granted, :bound_at])
    |> check_constraint(:granted, name: :grant_is_grantable)
    |> unique_constraint(:key_digest)
    |> unique_constraint([:device_id, :principal_id], name: :device_credentials_pkey)
    |> foreign_key_constraint(:device_id)
    |> foreign_key_constraint(:principal_id)
  end

  @doc """
  Revoking one credential, which leaves every other on the device usable.

  `granted` is deliberately not castable here: widening a grant would need a
  function that does not exist.
  """
  def revocation_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:revoked_at, :revoked_by])
    |> validate_required([:revoked_at, :revoked_by])
    |> check_constraint(:revoked_at, name: :revocation_is_attributed)
    |> foreign_key_constraint(:revoked_by)
  end
end
