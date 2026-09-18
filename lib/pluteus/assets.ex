defmodule Pluteus.Assets do
  @moduledoc """
  The household's custody of its stored bytes: what normalization may do, when
  an asset was last known good, and what deleting one takes with it.

  Its governing principle is spec-03's: recovery cannot be guaranteed, detection
  can. Nothing here repairs anything. A mismatch is recorded and surfaced, and
  what to do about it is a decision made against the backup copy with a person
  in the loop.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.AssetRole
  alias Pluteus.Catalog.Verification
  alias Pluteus.Repo

  @doc """
  Gives an asset a further role.
  """
  @spec add_role(Ecto.UUID.t(), atom(), String.t()) ::
          {:ok, AssetRole.t()} | {:error, Ecto.Changeset.t()}
  def add_role(asset_id, role_class, role) do
    %AssetRole{}
    |> AssetRole.changeset(%{asset_id: asset_id, role_class: role_class, role: role})
    |> Repo.insert()
  end

  @spec roles_of(Ecto.UUID.t()) :: [AssetRole.t()]
  def roles_of(asset_id) do
    Repo.all(from r in AssetRole, where: r.asset_id == ^asset_id, order_by: r.role)
  end

  @spec role_classes_of(Ecto.UUID.t()) :: [atom()]
  def role_classes_of(asset_id) do
    asset_id |> roles_of() |> Enum.map(& &1.role_class) |> Enum.uniq() |> Enum.sort()
  end

  @doc """
  Adopts an acquired asset as its own normalized master.

  spec-03 §4.2: where only a lossy record exists it is already the master,
  whatever its format. The bytes are not rewritten and no second asset appears —
  §5.5 forbids duplicating them so that each role may have a row.
  """
  @spec adopt_as_normalized(Ecto.UUID.t(), String.t()) ::
          {:ok, AssetRole.t()} | {:error, Ecto.Changeset.t()}
  def adopt_as_normalized(asset_id, role) do
    add_role(asset_id, :normalized, role)
  end

  @doc """
  Writes the standardized master produced from a lossless acquisition.

  Refuses a lossy source. spec-03 §4.2 forbids re-encoding lossy essence: there
  is no fidelity left to preserve, and the result is a generation worse than
  what it replaced.
  """
  @spec normalize(Ecto.UUID.t(), map(), String.t() | map()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def normalize(asset_id, attrs, name) do
    Multi.new()
    |> Multi.run(:source, fn repo, _changes -> lossless_source(repo, asset_id) end)
    |> Multi.run(:normalized, fn _repo, %{source: source} ->
      Catalog.create_asset(
        source.digital_item_id,
        Map.put(attrs, :essence, :lossless),
        name
      )
      |> case do
        {:ok, %{asset: asset}} -> {:ok, asset}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end)
    |> Multi.run(:role, fn _repo, %{normalized: normalized} ->
      add_role(normalized.id, :normalized, attrs[:role] || "standardized-master")
    end)
    |> Repo.transaction()
  end

  @doc """
  Records one verification attempt, successful or not.

  A successful attempt also moves the asset's last-known-good timestamp, which
  is the figure §5.3 measures the interval against. The two are written together
  so that the recorded log and the reported state cannot disagree.
  """
  @spec record_verification(Ecto.UUID.t(), atom(), DateTime.t()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def record_verification(asset_id, outcome, occurred_at \\ DateTime.utc_now()) do
    Multi.new()
    |> Multi.insert(
      :verification,
      Verification.changeset(%Verification{}, %{
        asset_id: asset_id,
        outcome: outcome,
        occurred_at: occurred_at
      })
    )
    |> Multi.run(:asset, fn repo, _changes ->
      mark_verified(repo, asset_id, outcome, occurred_at)
    end)
    |> Repo.transaction()
  end

  @spec verifications_of(Ecto.UUID.t()) :: [Verification.t()]
  def verifications_of(asset_id) do
    Repo.all(from v in Verification, where: v.asset_id == ^asset_id, order_by: v.occurred_at)
  end

  @doc """
  Every asset the household does not currently know to be intact.

  An asset that has never been verified is included. spec-03 §5.3 makes that the
  point: unverified is not corrupt, it is not knowing, and not knowing is the
  state that silently becomes loss.
  """
  @spec unverified(DateTime.t()) :: [Asset.t()]
  def unverified(now \\ DateTime.utc_now()) do
    Repo.all(
      from a in Asset,
        where:
          is_nil(a.verified_at) or
            fragment(
              "? + make_interval(secs => ?) < ?",
              a.verified_at,
              a.verification_interval_seconds,
              ^now
            )
    )
  end

  @doc """
  The normalized copies an asset supports (spec-01 §13.2).

  Only an acquired original supports anything: with it gone, nothing remains to
  prove the household held what the copy was made from. The coupling runs one
  way. A normalized copy supports nothing, because it is regenerable from the
  original by definition.

  An asset that itself carries the Acquired role is never coupled to another's
  deletion: it is its own support. That is the spec-03 §4.3 case, where a
  verified-reversible recompression assumes the Acquired role so the original
  can be discarded, and discarding it must leave the recompression standing.
  """
  @spec coupled_to(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def coupled_to(asset_id) do
    asset = Repo.get!(Asset, asset_id)

    if :acquired in role_classes_of(asset_id) do
      self_supporting =
        from r in AssetRole, where: r.role_class == :acquired, select: r.asset_id

      Repo.all(
        from a in Asset,
          join: r in AssetRole,
          on: r.asset_id == a.id,
          where: a.digital_item_id == ^asset.digital_item_id,
          where: r.role_class == :normalized,
          where: a.id != ^asset_id,
          where: a.id not in subquery(self_supporting),
          select: a.id,
          distinct: true
      )
    else
      []
    end
  end

  defp lossless_source(repo, asset_id) do
    case repo.get(Asset, asset_id) do
      nil ->
        {:error, :no_such_asset}

      %Asset{essence: :lossy} ->
        {:error, :lossy_essence_must_not_be_re_encoded}

      %Asset{} = asset ->
        {:ok, asset}
    end
  end

  defp mark_verified(repo, asset_id, :verified, occurred_at) do
    {count, _} =
      repo.update_all(
        from(a in Asset, where: a.id == ^asset_id),
        set: [verified_at: occurred_at, updated_at: DateTime.utc_now()]
      )

    {:ok, count}
  end

  defp mark_verified(_repo, _asset_id, outcome, _occurred_at)
       when outcome in [:mismatched, :unreadable] do
    {:ok, 0}
  end
end
