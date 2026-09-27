defmodule Pluteus.PrincipalFixtures do
  @moduledoc """
  Devices and the credentials principals hold on them (spec-06 §4.1).

  `Pluteus.Principals` gives a credential's grant no default, deliberately: §4.2
  makes a recorded grant a property of every credential, so a caller has to say
  what it is granting. A test that is not about narrowing wants everything the
  vocabulary holds, and says so once here rather than in every setup.

  `a_narrowed_credential/3` is the other case, and the one criterion 19 needs:
  spec-07 §4.3 gives `POST /devices` no grant parameter, so a strict subset is
  mintable only from code.
  """

  alias Pluteus.Authorization
  alias Pluteus.Principals
  alias Pluteus.Principals.Device

  @doc """
  A device a principal is enrolled on, granted everything its role permits.
  """
  @spec a_device(Ecto.UUID.t(), String.t()) :: Device.t()
  def a_device(principal_id, label) do
    {:ok, %{device: device}} =
      Principals.bind_device(principal_id, label, Authorization.grantable())

    device
  end

  @doc """
  A device with a client key, granted everything.
  """
  @spec a_key(Ecto.UUID.t(), String.t()) :: Principals.minted()
  def a_key(principal_id, label) do
    {:ok, minted} = Principals.mint_key(principal_id, label, Authorization.grantable())
    minted
  end

  @doc """
  A device with a client key granted only what is named.
  """
  @spec a_narrowed_credential(Ecto.UUID.t(), String.t(), [atom()]) :: Principals.minted()
  def a_narrowed_credential(principal_id, label, granted) do
    {:ok, minted} = Principals.mint_key(principal_id, label, granted)
    minted
  end

  @doc """
  A further principal enrolled on a device that already exists, with its own key.
  """
  @spec another_credential(Ecto.UUID.t(), Device.t()) :: Principals.minted()
  def another_credential(principal_id, %Device{} = device) do
    {:ok, minted} = Principals.mint_key_for(principal_id, device, Authorization.grantable())
    minted
  end
end
