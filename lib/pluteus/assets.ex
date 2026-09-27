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
  alias Pluteus.Catalog.Reconstruction
  alias Pluteus.Catalog.Verification
  alias Pluteus.Lifecycle
  alias Pluteus.PlatformEvents
  alias Pluteus.Principals
  alias Pluteus.Repo
  alias Pluteus.Storage

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

  Refuses any source whose essence is not lossless. spec-03 §4.2 forbids
  re-encoding lossy essence: there is no fidelity left to preserve, and the
  result is a generation worse than what it replaced. spec-04 §5.2 extends the
  refusal to essence that is unknown or not applicable, neither of which is
  known to have fidelity a re-encode would keep.
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
    |> Multi.run(:platform_event, fn _repo, %{verification: verification} ->
      announce(verification.outcome, asset_id, occurred_at)
    end)
    |> Repo.transaction()
  end

  # spec-01 §11.2's platform class: the household sees its holdings checked, and
  # this is the deployment's own scheduled work, so the System principal records it
  # (spec-06 §6.1). In the same transaction as the verification, so the log and the
  # feed cannot disagree about whether a check happened.
  #
  # Only a successful check. A mismatch or an unreadable asset is a finding, which
  # §9 gives its own surface, and announcing one as an event would put a failure
  # among the records of things that worked.
  #
  # Read from the recorded row rather than from the argument, so an outcome the
  # store rejects fails the insert before reaching here. The clauses are exhaustive
  # over the three §4 names and carry no catch-all, so a fourth raises.
  defp announce(:verified, asset_id, occurred_at),
    do:
      PlatformEvents.record(
        "verified",
        {:res, asset_id},
        Principals.system!().id,
        occurred_at
      )

  defp announce(outcome, _asset_id, _occurred_at) when outcome in [:mismatched, :unreadable],
    do: {:ok, :not_announced}

  @doc """
  Reads an asset's bytes, compares them with the digest recorded for it, and
  records the outcome.

  An asset in the recycle bin is verified like any other: its bytes are kept
  unchanged through the window so that restoring it is exact, and that promise
  is only as good as the check behind it.

  Raises for a digest algorithm this system cannot compute. A digest nothing can
  check is not an unverified asset but an unverifiable one, and that is a
  defect in the record, not an outcome of reading it.
  """
  @spec verify(Ecto.UUID.t(), DateTime.t()) :: {:ok, map()} | {:error, atom(), term(), map()}
  def verify(asset_id, now \\ DateTime.utc_now()) do
    asset = Repo.get!(Asset, asset_id)
    expected = String.downcase(asset.digest)

    outcome =
      case Storage.digest(asset.location, algorithm!(asset.digest_algorithm)) do
        {:ok, ^expected} -> :verified
        {:ok, _other} -> :mismatched
        {:error, _reason} -> :unreadable
      end

    record_verification(asset_id, outcome, now)
  end

  defp algorithm!("sha-256"), do: :sha256
  defp algorithm!("sha-512"), do: :sha512

  defp algorithm!(other) do
    raise ArgumentError, "no digest algorithm #{inspect(other)} is supported"
  end

  @doc """
  Every asset whose most recent check found something wrong: a mismatch, or
  bytes that could not be read.

  This is not the unverified list. spec-03 §5.3 keeps the two apart: unverified
  means the household does not currently know, and a finding means it does.
  """
  @spec findings() :: [map()]
  def findings do
    from(v in Verification,
      distinct: v.asset_id,
      order_by: [desc: v.occurred_at, desc: v.inserted_at],
      select: %{asset_id: v.asset_id, outcome: v.outcome, occurred_at: v.occurred_at}
    )
    |> Repo.all()
    |> Enum.reject(&(&1.outcome == :verified))
  end

  @doc """
  Discards an acquired original in favour of a recompression that reproduces it
  (spec-03 §4.3).

  `reconstructed` is the location of bytes rebuilt from the recompression. Their
  digest is computed here and must equal the original's; a digest supplied by
  whatever did the rebuilding would be the codec's claim, which §4.3 forbids
  relying on. On a match the evidence is recorded, the recompression assumes the
  Acquired role, and the original goes to the recycle bin — alone, because an
  asset holding the Acquired role is its own support. On any mismatch nothing
  changes.
  """
  @spec discard_original(Ecto.UUID.t(), Ecto.UUID.t(), String.t(), Ecto.UUID.t()) ::
          {:ok, Pluteus.Lifecycle.Recycling.t()} | {:error, term()}
  def discard_original(original_id, recompression_id, reconstructed, principal_id) do
    original = Repo.get!(Asset, original_id)
    recompression = Repo.get!(Asset, recompression_id)
    algorithm = algorithm!(original.digest_algorithm)

    with :ok <- one_holding(original, recompression),
         :ok <- acquired(original),
         {:ok, digest} <- reconstruction_digest(reconstructed, algorithm),
         :ok <- reproduces(digest, original) do
      Repo.transaction(fn -> commit_discard(original, recompression, digest, principal_id) end)
    end
  end

  defp commit_discard(original, recompression, digest, principal_id) do
    {:ok, _} =
      %Reconstruction{}
      |> Reconstruction.changeset(%{
        original_id: original.id,
        recompression_id: recompression.id,
        digest: digest,
        digest_algorithm: original.digest_algorithm,
        verified_by: principal_id,
        verified_at: DateTime.utc_now()
      })
      |> Repo.insert()

    {:ok, _} = add_role(recompression.id, :acquired, "reversible-recompression")

    case Lifecycle.recycle(original.id, principal_id) do
      {:ok, recycling} -> recycling
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp one_holding(%Asset{digital_item_id: same}, %Asset{digital_item_id: same}), do: :ok
  defp one_holding(_original, _recompression), do: {:error, :not_one_holding}

  defp acquired(%Asset{id: id}) do
    if :acquired in role_classes_of(id), do: :ok, else: {:error, :original_is_not_acquired}
  end

  defp reconstruction_digest(location, algorithm) do
    case Storage.digest(location, algorithm) do
      {:ok, digest} -> {:ok, digest}
      {:error, reason} -> {:error, {:reconstruction_unreadable, reason}}
    end
  end

  defp reproduces(digest, %Asset{digest: expected}) do
    if digest == String.downcase(expected),
      do: :ok,
      else: {:error, :reconstruction_does_not_match}
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

  Where a digital item is realized by parts, the coupling is per part: disc
  two's original supports disc two's normalized copy and not disc one's
  (spec-04 §7).
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
          where: fragment("? IS NOT DISTINCT FROM ?", a.part_sequence, ^asset.part_sequence),
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

      %Asset{essence: :lossless} = asset ->
        {:ok, asset}

      %Asset{essence: essence} ->
        {:error, {:only_lossless_essence_is_re_encoded, essence}}
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
