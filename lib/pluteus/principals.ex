defmodule Pluteus.Principals do
  @moduledoc """
  Reads and writes over the identities that use the system.

  Nothing outside this module refers to an `(issuer, subject)` composite. §10.1
  requires every reference to be to the principal's locally minted identifier,
  which is what makes a provider migration a remapping rather than a new
  principal with an empty history.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Pluteus.Authorization
  alias Pluteus.Catalog.Res
  alias Pluteus.Principals.Device
  alias Pluteus.Principals.DeviceCredential
  alias Pluteus.Principals.Identity
  alias Pluteus.Principals.Principal
  alias Pluteus.Repo

  @doc """
  Mints a principal under a role.

  Pass `:person_id` to link it to the LRM person it corresponds to. Leave it out
  for the deployment itself, which acts as a principal and is nobody.
  """
  @spec create_principal(map()) :: {:ok, Principal.t()} | {:error, Ecto.Changeset.t() | atom()}
  def create_principal(attrs) do
    Multi.new()
    |> Multi.run(:person_kind, fn repo, _changes -> person_kind(repo, attrs[:person_id]) end)
    |> Multi.insert(:principal, fn %{person_kind: person_kind} ->
      Principal.changeset(%Principal{}, put_person_kind(attrs, person_kind))
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{principal: principal}} -> {:ok, principal}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Records that a provider knows this principal by an `(issuer, subject)` pair.

  A principal may hold several. An issuer change is a second pair against the
  same principal, not a second principal.
  """
  @spec bind_identity(Ecto.UUID.t(), String.t(), String.t()) ::
          {:ok, Identity.t()} | {:error, Ecto.Changeset.t()}
  def bind_identity(principal_id, issuer, subject) do
    %Identity{}
    |> Identity.changeset(%{principal_id: principal_id, issuer: issuer, subject: subject})
    |> Repo.insert()
  end

  @doc """
  Moves an existing binding to a new issuer.

  §10.1 names this repair directly: the composite changed, the principal did
  not, so the mapping is rewritten and every reference to the principal — events
  included — is untouched because none of them held the composite.
  """
  @spec rebind_issuer(String.t(), String.t(), String.t()) :: non_neg_integer()
  def rebind_issuer(old_issuer, new_issuer, subject) do
    {count, _} =
      Repo.update_all(
        from(i in Identity, where: i.issuer == ^old_issuer and i.subject == ^subject),
        set: [issuer: new_issuer, updated_at: DateTime.utc_now()]
      )

    count
  end

  @doc """
  The principal an identity the provider has admitted belongs to, created as a
  Member the first time the identity arrives (spec-06 §6.1).

  Two first requests from one person can arrive together. The identity pair is
  unique, so the second insert is refused, and the principal the first created
  is the answer to both.
  """
  @spec admit(String.t(), String.t()) :: Principal.t()
  def admit(issuer, subject) do
    case principal_for(issuer, subject) do
      %Principal{} = principal -> principal
      nil -> first_arrival(issuer, subject)
    end
  end

  defp first_arrival(issuer, subject) do
    case Repo.transaction(fn -> create_member(issuer, subject) end) do
      {:ok, principal} -> principal
      {:error, :identity_taken} -> principal_for(issuer, subject)
    end
  end

  defp create_member(issuer, subject) do
    {:ok, principal} = create_principal(%{role: "member"})

    case bind_identity(principal.id, issuer, subject) do
      {:ok, _identity} ->
        principal

      {:error, changeset} ->
        if taken?(changeset),
          do: Repo.rollback(:identity_taken),
          else: raise(Ecto.InvalidChangesetError, action: :insert, changeset: changeset)
    end
  end

  defp taken?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, opts}} -> opts[:constraint] == :unique end)
  end

  @doc """
  The principal a provider's `(issuer, subject)` pair names, if any.
  """
  @spec principal_for(String.t(), String.t()) :: Principal.t() | nil
  def principal_for(issuer, subject) do
    Repo.one(
      from p in Principal,
        join: i in Identity,
        on: i.principal_id == p.id,
        where: i.issuer == ^issuer and i.subject == ^subject
    )
  end

  @spec get_principal(Ecto.UUID.t()) :: Principal.t() | nil
  def get_principal(id), do: Repo.get(Principal, id)

  @doc """
  The person each of many principals is, where one is recorded.

  A surface naming several principals — whoever marked a passage, whoever cleared a
  finding — resolves their names in one pass rather than one lookup each. A principal
  that is nobody is absent from the answer rather than present as nothing, since the
  deployment itself acts as one.
  """
  @spec people([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => Ecto.UUID.t()}
  def people([]), do: %{}

  def people(principal_ids) do
    Map.new(
      Repo.all(
        from p in Principal,
          where: p.id in ^principal_ids and not is_nil(p.person_id),
          select: {p.id, p.person_id}
      )
    )
  end

  @doc """
  The deployment's own principal, minted at onboarding (spec-06 §6.5).
  Raises before onboarding, when there is none: whatever asked has nothing to
  act as.
  """
  @spec system!() :: Principal.t()
  def system!, do: Repo.get_by!(Principal, role: "system")

  @doc """
  Whether an `(issuer, subject)` pair currently authenticates as the principal.
  """
  @spec authenticates_as?({String.t(), String.t()}, Ecto.UUID.t()) :: boolean()
  def authenticates_as?({issuer, subject}, principal_id) do
    case principal_for(issuer, subject) do
      %Principal{id: ^principal_id} -> true
      _other -> false
    end
  end

  @doc """
  Enrols a principal on a new device, taking a credential on it (spec-06 §4).

  `granted` is §4.2's recorded grant and has no default; pass
  `Pluteus.Authorization.grantable_to/1` for everything the role permits.
  """
  @spec bind_device(Ecto.UUID.t(), String.t(), [atom()], DateTime.t()) ::
          {:ok, %{device: Device.t(), credential: DeviceCredential.t()}}
          | {:error, Ecto.Changeset.t()}
  def bind_device(principal_id, label, granted, now \\ DateTime.utc_now()) do
    Multi.new()
    |> Multi.insert(:device, Device.changeset(%Device{}, %{label: label}))
    |> Multi.insert(:credential, fn %{device: device} ->
      credential_changeset(device.id, principal_id, granted, nil, now)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{device: device, credential: credential}} ->
        {:ok, %{device: device, credential: credential}}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Takes a further credential on a device that already exists (spec-06 §4.1).

  The device's label is not given again: it belongs to the device rather than to
  any credential on it, and a second principal enrolling does not rename the
  screen for the first.
  """
  @spec bind_credential(Ecto.UUID.t(), Ecto.UUID.t(), [atom()], DateTime.t()) ::
          {:ok, DeviceCredential.t()} | {:error, Ecto.Changeset.t()}
  def bind_credential(principal_id, device_id, granted, now \\ DateTime.utc_now()) do
    device_id
    |> credential_changeset(principal_id, granted, nil, now)
    |> Repo.insert()
  end

  @doc """
  The device a browser is, for one principal (spec-06 §4.1).

  A browser profile is a device: a position, a queue and an event are keyed by device
  ([spec-01] §11.4), and the composite foreign key requires that device be one the
  principal holds a credential on, so the interface cannot record where anybody is
  until it has one. The credential carries no key, which `key_digest` admits and the
  partial unique index on it allows: a browser authenticates through the proxy, so
  there is no key to mint and `for_key/1` cannot reach it.

  `claimed` is what the browser says it is, and a browser can say anything. It is
  safe to believe because a device is not an identity and accumulates nothing of its
  own: the credential a principal takes here names that principal, the foreign key
  admits no other, and so a browser naming a device belonging to somebody else gains
  a credential of its own on it and reads nothing. That is also §4.1 working as
  written — two members sharing a browser are one screen with two credentials, which
  is why `player_number` belongs to the device.

  A revoked credential is reported rather than replaced. Minting a second one would
  undo in silence the thing the person did deliberately.
  """
  @spec device_for_browser(Principal.t(), Ecto.UUID.t() | nil, String.t()) ::
          {:ok, Device.t()} | {:revoked, Device.t()}
  def device_for_browser(%Principal{} = principal, claimed, label) do
    case claimed && Repo.get(Device, claimed) do
      nil -> mint_browser(principal, label)
      device -> credential_for_browser(principal, device)
    end
  end

  defp credential_for_browser(principal, device) do
    case credential_on(principal.id, device.id) do
      %DeviceCredential{revoked_at: nil} ->
        {:ok, device}

      %DeviceCredential{} ->
        {:revoked, device}

      nil ->
        {:ok, _credential} =
          bind_credential(principal.id, device.id, Authorization.grantable_to(principal))

        {:ok, device}
    end
  end

  defp mint_browser(principal, label) do
    {:ok, %{device: device}} =
      bind_device(principal.id, label, Authorization.grantable_to(principal))

    {:ok, device}
  end

  @doc """
  Enrols a principal on a new device and mints that credential's client key
  (spec-07 §3.2).

  The key is returned once, here, and never stored: only its digest is. It
  carries 256 bits from the system's secure random source, so a fast digest
  is enough to keep it; it is not a password, and nobody chose it.
  """
  @spec mint_key(Ecto.UUID.t(), String.t(), [atom()], DateTime.t()) ::
          {:ok, minted()} | {:error, Ecto.Changeset.t()}
  def mint_key(principal_id, label, granted, now \\ DateTime.utc_now()) do
    key = new_key()

    Multi.new()
    |> Multi.insert(:device, Device.changeset(%Device{}, %{label: label}))
    |> Multi.insert(:credential, fn %{device: device} ->
      credential_changeset(device.id, principal_id, granted, key_digest(key), now)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{device: device, credential: credential}} ->
        {:ok, %{device: device, credential: credential, key: key}}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Mints a client key for a principal on a device that already exists
  (spec-06 §4.1).
  """
  @spec mint_key_for(Ecto.UUID.t(), Device.t(), [atom()], DateTime.t()) ::
          {:ok, minted()} | {:error, Ecto.Changeset.t()}
  def mint_key_for(principal_id, %Device{} = device, granted, now \\ DateTime.utc_now()) do
    key = new_key()

    device.id
    |> credential_changeset(principal_id, granted, key_digest(key), now)
    |> Repo.insert()
    |> case do
      {:ok, credential} -> {:ok, %{device: device, credential: credential, key: key}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @typedoc """
  A credential and the key shown once for it.
  """
  @type minted :: %{device: Device.t(), credential: DeviceCredential.t(), key: String.t()}

  @doc """
  The principal, device and credential a client key belongs to, or `:invalid_key`
  where no credential holds it, that credential is revoked, or its principal is
  retired (spec-07 §3.2).

  A key names one credential, so revoking one leaves every other credential on the
  same device answering as before, and no credential is reachable by the principal
  of another (§4.1).
  """
  @spec for_key(String.t()) ::
          {:ok, %{principal: Principal.t(), device: Device.t(), credential: DeviceCredential.t()}}
          | {:error, :invalid_key}
  def for_key(key) when is_binary(key) do
    with %DeviceCredential{revoked_at: nil} = credential <-
           Repo.get_by(DeviceCredential, key_digest: key_digest(key)),
         %Principal{retired_at: nil} = principal <-
           Repo.get!(Principal, credential.principal_id) do
      {:ok,
       %{
         principal: principal,
         device: Repo.get!(Device, credential.device_id),
         credential: credential
       }}
    else
      _unknown_revoked_or_retired -> {:error, :invalid_key}
    end
  end

  defp new_key, do: "pk_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  defp key_digest(key), do: :sha256 |> :crypto.hash(key) |> Base.encode16(case: :lower)

  defp credential_changeset(device_id, principal_id, granted, key_digest, now) do
    DeviceCredential.changeset(%DeviceCredential{}, %{
      device_id: device_id,
      principal_id: principal_id,
      granted: granted,
      key_digest: key_digest,
      bound_at: now
    })
  end

  @doc """
  Every credential a principal holds, its device preloaded.

  This is the unit spec-10 criterion 55 makes revocable, so it is what a surface
  listing "my devices" shows.
  """
  @spec credentials_of(Ecto.UUID.t()) :: [DeviceCredential.t()]
  def credentials_of(principal_id) do
    Repo.all(
      from c in DeviceCredential,
        where: c.principal_id == ^principal_id,
        order_by: c.bound_at,
        preload: [:device]
    )
  end

  @doc """
  Every device a principal holds a credential on, revoked credentials included.

  Revoked ones stay, because a session recorded before a revocation still names
  the device and a surface reporting that session has to name it too.
  """
  @spec devices_of(Ecto.UUID.t()) :: [Device.t()]
  def devices_of(principal_id) do
    Repo.all(
      from d in Device,
        join: c in DeviceCredential,
        on: c.device_id == d.id,
        where: c.principal_id == ^principal_id,
        order_by: c.bound_at
    )
  end

  @doc """
  One principal's credential on one device, or nil.
  """
  @spec credential_on(Ecto.UUID.t(), Ecto.UUID.t()) :: DeviceCredential.t() | nil
  def credential_on(principal_id, device_id) do
    Repo.get_by(DeviceCredential, principal_id: principal_id, device_id: device_id)
  end

  @doc """
  Every `(issuer, subject)` pair bound to a principal.
  """
  @spec identities_of(Ecto.UUID.t()) :: [Identity.t()]
  def identities_of(principal_id) do
    Repo.all(from i in Identity, where: i.principal_id == ^principal_id)
  end

  defp person_kind(_repo, nil), do: {:ok, nil}

  defp person_kind(repo, person_id) do
    case repo.get(Res, person_id) do
      nil -> {:error, :no_such_res}
      %Res{kind: kind} -> {:ok, kind}
    end
  end

  defp put_person_kind(attrs, nil), do: attrs
  defp put_person_kind(attrs, person_kind), do: Map.put(attrs, :person_kind, person_kind)
end
