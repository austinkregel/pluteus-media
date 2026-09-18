defmodule Pluteus.Onboarding do
  @moduledoc """
  How a deployment gets its first Administrator (spec-06 §6.5).

  The authentication path maps an identity onto a principal that already
  exists, so it cannot create the first. Onboarding does, on evidence of host
  access: at start, a deployment with no principals writes a one-time secret to
  its console, and whoever presents that secret while authenticated becomes the
  Administrator. The System principal is minted at the same moment, with no
  identity mapping. Once any principal exists, onboarding refuses everything.
  """

  require Logger

  alias Pluteus.Household
  alias Pluteus.Household.TrustBoundary
  alias Pluteus.Principals
  alias Pluteus.Principals.Principal
  alias Pluteus.Repo

  @doc """
  Issues a fresh one-time secret and stores its digest, if the deployment has
  no principals. The secret itself is returned and never stored.
  """
  @spec prepare(DateTime.t()) :: {:ok, String.t()} | {:error, :already_onboarded}
  def prepare(now \\ DateTime.utc_now()) do
    if onboarded?() do
      {:error, :already_onboarded}
    else
      secret = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

      {:ok, _boundary} =
        Household.boundary()
        |> TrustBoundary.changeset(%{
          onboarding_secret_digest: digest(secret),
          onboarding_issued_at: now
        })
        |> Repo.insert_or_update()

      {:ok, secret}
    end
  end

  @doc """
  Writes a fresh secret to the console at start, when onboarding is still open.
  """
  @spec announce() :: :ok
  def announce do
    case prepare() do
      {:ok, secret} ->
        Logger.warning(
          "No principals exist. POST this one-time secret to /onboarding while " <>
            "signed in through the proxy to become the first Administrator: #{secret}"
        )

      {:error, :already_onboarded} ->
        :ok
    end
  end

  @doc """
  Establishes the System principal and the first Administrator, mapped to the
  identity the claimant is authenticated as.
  """
  @spec claim(String.t(), {String.t(), String.t()}) ::
          {:ok, %{administrator: Principal.t(), system: Principal.t()}} | {:error, atom()}
  def claim(secret, {issuer, subject}) do
    Repo.transaction(fn ->
      with :ok <- still_open(),
           :ok <- secret_matches(secret),
           {:ok, system} <- Principals.create_principal(%{role: "system"}),
           {:ok, administrator} <- Principals.create_principal(%{role: "administrator"}),
           {:ok, _identity} <- Principals.bind_identity(administrator.id, issuer, subject) do
        {:ok, _boundary} =
          Household.boundary()
          |> TrustBoundary.changeset(%{onboarding_secret_digest: nil})
          |> Repo.update()

        %{administrator: administrator, system: system}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec onboarded?() :: boolean()
  def onboarded?, do: Repo.exists?(Principal)

  defp still_open do
    if onboarded?(), do: {:error, :already_onboarded}, else: :ok
  end

  defp secret_matches(secret) do
    case Household.boundary() do
      %TrustBoundary{onboarding_secret_digest: stored} when is_binary(stored) ->
        if Plug.Crypto.secure_compare(stored, digest(secret)),
          do: :ok,
          else: {:error, :wrong_secret}

      %TrustBoundary{} ->
        {:error, :no_secret_issued}
    end
  end

  defp digest(secret), do: :sha256 |> :crypto.hash(secret) |> Base.encode16(case: :lower)
end
