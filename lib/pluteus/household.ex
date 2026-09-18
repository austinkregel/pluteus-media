defmodule Pluteus.Household do
  @moduledoc """
  The household as the deployment's trust boundary (spec-06 §5).

  It is also a collective agent in the catalog, and the two are kept apart by
  holding nothing in common. The trust boundary holds membership, policy and
  device bindings and has no name; the collective agent holds names, creation
  and assignment and has no membership list. The one link between them is the
  trust boundary's reference to the collective agent, so renaming the household
  is a naming operation with no second write.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Household.TrustBoundary
  alias Pluteus.Principals.Principal
  alias Pluteus.Repo

  @doc """
  Links the trust boundary to the collective agent the household is in the
  catalog. A deployment may exist before this is done (§5.3).
  """
  @spec link(Ecto.UUID.t()) :: {:ok, TrustBoundary.t()} | {:error, term()}
  def link(collective_agent_id) do
    case Repo.get(Res, collective_agent_id) do
      nil ->
        {:error, :no_such_res}

      %Res{kind: kind} ->
        boundary()
        |> TrustBoundary.changeset(%{
          collective_agent_id: collective_agent_id,
          collective_agent_kind: kind
        })
        |> Repo.insert_or_update()
    end
  end

  @doc """
  The household's name, resolved from the collective agent's nomens like any
  other res's (spec-01 §7.4). A household not yet linked has none.
  """
  @spec name(Profile.t()) :: {:ok, String.t()} | :unnamed
  def name(%Profile{} = profile) do
    case boundary() do
      %TrustBoundary{collective_agent_id: nil} ->
        :unnamed

      %TrustBoundary{collective_agent_id: id} ->
        {:ok, Resolution.resolve(id, profile).nomen_string}
    end
  end

  @doc """
  The principals currently inside the trust boundary.
  """
  @spec members() :: [Principal.t()]
  def members do
    Repo.all(
      from p in Principal,
        where: p.role in ["administrator", "member"] and is_nil(p.retired_at)
    )
  end

  @spec boundary() :: TrustBoundary.t()
  def boundary do
    Repo.get(TrustBoundary, true) || %TrustBoundary{singleton: true}
  end
end
