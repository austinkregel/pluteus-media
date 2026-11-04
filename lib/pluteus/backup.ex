defmodule Pluteus.Backup do
  @moduledoc """
  What a backup must hold, and what it must not spend capacity on (spec-01
  §13.7, spec-03 §7).

  The division is regenerability. Acquired originals, normalized masters,
  authored annotations, events and the catalog itself cannot be recomputed from
  anything else the household keeps; derived assets and derived annotations can,
  from a master and a recipe. The catalog is the easiest thing to leave out,
  because it is not a media file, and the only thing that makes the media files
  more than a directory of unnamed bytes.

  Every table is classified here. A table missing from the classification is a
  test failure, so a new one cannot be left out of the backup by oversight.

  That holds for every database. The queue and the corpora have servers of their own, and a
  classification that only covered the catalogue would make the guarantee above true of one
  database and silently untrue of the others — so `queue_classification/0` answers for the
  queue's and `corpus_classification/0` for the corpora's, where everything is excluded:
  the queue is operational state the schedule rebuilds, and a corpus is refetched.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Annotations.Annotation
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.AssetRole
  alias Pluteus.Catalog.Verification

  @whole ~w(
    res nomens works expressions manifestations items embodiments work_parts
    manifestation_parts work_inspirations
    aggregations digital_items extents associations principals
    principal_identities principal_preferences principal_expression_choices
    events platform_events resume_positions recyclings recycled_res
    tombstones reconstructions duplicate_candidates schema_migrations
    trust_boundary devices device_credentials audit_records catalog_writes work_creators
    acquisitions ingest_findings categories release_keys artist_keys serial_keys
    narration_keys time_span_keys
    analysis_sources credits musicbrainz_artists
    stars ratings playlists playlist_entries play_queues play_queue_entries
  )

  @selected ~w(assets asset_roles verifications addresses annotations)

  # Provenance of derived data goes with the derived data. The job queue is
  # operational state, rebuilt by the schedule, and so are inbox sightings,
  # which the next pass over the inbox takes again. What is playing now is
  # stale by the time any backup could be restored.
  #
  # A presentation asset is regenerable from the master it names ([spec-10] §11.1),
  # which is why it is evictable at all; copying one would spend capacity on
  # something the deployment throws away on purpose. Its eviction log is the record
  # of that throwing away, and means nothing once the rows it counted are gone.
  @excluded ~w(
    tool_versions derivations inbox_sightings now_playing
    presentation_assets presentation_evictions
  )

  # The queue's own database holds these and nothing else. Its own record of which
  # migrations have run is excluded with them: it describes a database that is not
  # backed up, so restoring it would mean restoring the queue.
  @queue ~w(oban_jobs oban_peers schema_migrations)

  # The corpora's database, the same way: published data refetched after loss (spec-05
  # §5.7), and the record of which snapshot of each was held, which describes a copy that
  # is not backed up. A corpus importer's own tables live in schemas of their own, named
  # here as `schema.table`, and are answered for as they arrive.
  @corpora ~w(corpus_snapshots schema_migrations)

  @doc """
  Every table of the catalogue's database, classified as backed up whole, backed up in
  part, or excluded.
  """
  @spec classification() :: %{String.t() => :whole | :selected | :excluded}
  def classification do
    Map.new(
      Enum.map(@whole, &{&1, :whole}) ++
        Enum.map(@selected, &{&1, :selected}) ++ Enum.map(@excluded, &{&1, :excluded})
    )
  end

  @doc """
  Every table of the queue's database, which is all of them and all excluded.

  Said as a classification rather than as a sentence, so that a table appearing in that
  database is answered for by the same test that answers for the catalogue's. A queue
  that grew a table nobody had thought about would otherwise be the one place the
  guarantee above does not reach.
  """
  @spec queue_classification() :: %{String.t() => :excluded}
  def queue_classification, do: Map.new(@queue, &{&1, :excluded})

  @doc """
  Every table of the corpora's database, all excluded: a corpus is the publisher's data
  and is refetched after loss.
  """
  @spec corpus_classification() :: %{String.t() => :excluded}
  def corpus_classification, do: Map.new(@corpora, &{&1, :excluded})

  @doc """
  The rows of a partly backed-up table that the backup holds.
  """
  @spec selection(String.t()) :: Ecto.Query.t()
  def selection("assets"), do: backed_up_assets()

  def selection("asset_roles") do
    from r in AssetRole, where: r.asset_id in subquery(backed_up_asset_ids())
  end

  def selection("verifications") do
    from v in Verification, where: v.asset_id in subquery(backed_up_asset_ids())
  end

  def selection("addresses"), do: from(a in Address, where: is_nil(a.derivation_id))
  def selection("annotations"), do: from(a in Annotation, where: not is_nil(a.principal_id))

  # A redundant copy is itself the backup, and a derived one is regenerable, so
  # only the acquired and normalized classes are copied.
  defp backed_up_assets do
    from a in Asset, where: a.id in subquery(backed_up_asset_ids())
  end

  defp backed_up_asset_ids do
    from r in AssetRole,
      where: r.role_class in [:acquired, :normalized],
      distinct: true,
      select: r.asset_id
  end
end
