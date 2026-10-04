defmodule Pluteus.Television.Registry do
  @moduledoc """
  §18.2's endpoint groups and §18.3's credential policy, which spec-10 §20 holds for the
  television contract.

  §18.1's projected API version is §20's too, and `projected_api_version/0` raises where
  the registry holds none. That string is a behaviour switch in the client rather than
  decoration, so a value supplied in the registry's place would make the client behave as
  though the deployment answered endpoints it does not.
  """

  alias Pluteus.Registry

  @source "television"

  @doc """
  The endpoint groups the deployment projects (§18.2).

  Playback negotiation is where spec-08 §14.1's rendition endpoints are reached, so they
  are that group rather than one of their own.
  """
  @spec projected_endpoints() :: [String.t()]
  def projected_endpoints, do: Map.fetch!(fetch("projected_endpoints"), "groups")

  @doc """
  Whether a television holds one credential or several (§18.3).
  """
  @spec credentials_per_device() :: String.t()
  def credentials_per_device, do: Map.fetch!(policy(), "credentials_per_device")

  @doc """
  What kind of credential a television holds once enrolled.
  """
  @spec credential_kind() :: String.t()
  def credential_kind, do: Map.fetch!(policy(), "credential_kind")

  @doc """
  How a television is enrolled (§18.3).
  """
  @spec enrolment() :: String.t()
  def enrolment, do: Map.fetch!(policy(), "enrolment")

  @doc """
  The API version string §18.1 declares.

  Raises where the registry holds none, because a declared version the client switches
  behaviour on is not a value any code path may supply in the registry's place.
  """
  @spec projected_api_version() :: String.t()
  def projected_api_version, do: Map.fetch!(registry(), "projected_api_version")

  defp policy, do: fetch("credential_policy")

  defp fetch(key), do: Map.fetch!(registry(), key)

  defp registry, do: Registry.read(@source)
end
