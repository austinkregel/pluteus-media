defmodule Pluteus.Analysis do
  @moduledoc """
  Running deriving tools over holdings and keeping what they measure
  (spec-04 §8, spec-02).

  An input is what a derivation ran over: a manifestation for whole-file
  analysis, a stream's `track` address for one stream of a container, and a
  track manifestation for one track of a release held in one file. A tool
  reads the normalized master of the input's analysis source, and the asset it
  read is recorded in the derivation's parameters.

  Due work is found from recorded state. An input is due for a tool when
  nothing has been derived from it at the tool's current version and no
  uncleared finding stands against it at that version. A tool reporting a
  version not seen before is recorded at once, so everything analysed at an
  earlier version is due before anything is analysed at the new one.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Actor
  alias Pluteus.Analysis.Source
  alias Pluteus.Annotations
  alias Pluteus.Annotations.Derivation
  alias Pluteus.Annotations.ToolVersion
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.Association
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Finding
  alias Pluteus.Ingest.Identify
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Probe
  alias Pluteus.Ingest.Streams
  alias Pluteus.Lifecycle
  alias Pluteus.Principals
  alias Pluteus.Repo
  alias Pluteus.Representation.Registry, as: FieldRegistry
  alias Pluteus.Storage

  @typedoc """
  One thing a tool is run over.

  `part_sequence` names which file of the holding carries the bytes, since a reading in
  several files has a master per part and `source_id` alone does not say which.
  """
  @type input :: %{
          input_id: Ecto.UUID.t(),
          source_id: Ecto.UUID.t(),
          part_sequence: integer() | nil,
          stream: map() | nil,
          start_ms: non_neg_integer() | nil,
          end_ms: non_neg_integer() | nil
        }

  @doc """
  The tools configured to run, by module.
  """
  @spec tools() :: [module()]
  def tools, do: config(:tools)

  @doc """
  Asks a tool what it is and records its version the first time it is seen.
  """
  @spec describe(module()) :: {:ok, map()} | {:error, :transient | :permanent, term()}
  def describe(tool) do
    with {:ok, %{name: name, version: version} = description} <- tool.describe() do
      {:ok, _} = Annotations.record_tool_version(name, version)
      {:ok, description}
    end
  end

  @doc """
  Every input analysis runs over: each live holding with audio content and a
  normalized master, as a whole file or, for a container, per audio stream;
  and each track of a release held in one file.
  """
  @spec inputs() :: [input()]
  def inputs do
    placed =
      Repo.all(
        from a in Acquisition,
          join: s in Source,
          on: s.digital_item_id == a.digital_item_id,
          where: a.state == :placed and a.media_class in [:audio, :video],
          select: {a, s.manifestation_id}
      )

    originals = originals_of(for {acquisition, _manifestation} <- placed, do: acquisition.id)

    placed
    |> Enum.filter(fn {acquisition, manifestation_id} ->
      original = Map.fetch!(originals, acquisition.id)

      live?(manifestation_id) and
        not is_nil(Normalize.master_of(acquisition.digital_item_id, original.part_sequence))
    end)
    |> Enum.flat_map(fn {acquisition, manifestation_id} ->
      inputs_of(acquisition, manifestation_id, Map.fetch!(originals, acquisition.id))
    end)
  end

  # The asset a placed acquisition became, which carries which part of its holding the
  # bytes are. Fetched for the whole pass, and by key rather than by join: a placed
  # acquisition that became no asset is a broken invariant, and `Map.fetch!` says so
  # where an inner join would drop it in silence.
  defp originals_of(acquisition_ids) do
    Map.new(Repo.all(from a in Asset, where: a.id in ^acquisition_ids), &{&1.id, &1})
  end

  defp inputs_of(acquisition, manifestation_id, original) do
    audio_tracks =
      manifestation_id
      |> Catalog.addresses_of()
      |> Enum.filter(&(&1.selector_type == :track and &1.stream_kind == :audio))

    extents = extents_on(manifestation_id)

    cond do
      audio_tracks != [] ->
        Enum.map(audio_tracks, &%{input(&1.id, acquisition, original) | stream: selector_of(&1)})

      extents != [] ->
        Enum.map(extents, fn {track_id, address} ->
          %{
            input(track_id, acquisition, original)
            | start_ms: address.start_ms,
              end_ms: address.end_ms
          }
        end)

      acquisition.media_class == :audio ->
        [input(whole_or_part(manifestation_id, acquisition, original), acquisition, original)]

      true ->
        []
    end
  end

  # A holding carried by one file is analysed as the manifestation it embodies. A reading
  # in several files is analysed a part at a time, and what identifies a part is its own
  # asset: keyed by the manifestation, every part of one reading would be the same input
  # and the last run would supersede the rest.
  defp whole_or_part(manifestation_id, _acquisition, %Asset{part_sequence: nil}),
    do: manifestation_id

  defp whole_or_part(_manifestation_id, acquisition, %Asset{}), do: acquisition.id

  defp input(input_id, acquisition, original) do
    %{
      input_id: input_id,
      source_id: acquisition.digital_item_id,
      part_sequence: original.part_sequence,
      stream: nil,
      start_ms: nil,
      end_ms: nil
    }
  end

  defp extents_on(manifestation_id) do
    Repo.all(
      from a in Address,
        join: l in Association,
        on: l.subject_id == a.id and l.refinement == "extent-of",
        where: a.target_id == ^manifestation_id and a.selector_type == :temporal,
        order_by: a.start_ms,
        select: {l.object_id, a}
    )
  end

  defp selector_of(%Address{} = address) do
    %{
      selector_type: :track,
      stream_kind: address.stream_kind,
      stream_language: address.stream_language,
      stream_disposition: address.stream_disposition,
      stream_channels: address.stream_channels,
      stream_ordinal: address.stream_ordinal
    }
  end

  @doc """
  The input with an identifier, or nil where it is no longer analysable.
  """
  @spec input(Ecto.UUID.t()) :: input() | nil
  def input(input_id), do: Enum.find(inputs(), &(&1.input_id == input_id))

  @doc """
  The inputs due for a tool at a version.
  """
  @spec due(String.t(), String.t()) :: [input()]
  def due(tool_name, version) do
    tool_version = Repo.get_by!(ToolVersion, tool: tool_name, version: version)

    done =
      MapSet.new(
        Repo.all(
          from d in Derivation,
            where: d.tool_version_id == ^tool_version.id,
            select: d.input_id
        ) ++
          Repo.all(
            from f in Finding,
              where: f.stage == :analyse and f.tool_version_id == ^tool_version.id,
              where: is_nil(f.cleared_at),
              select: f.input_id
          )
      )

    Enum.reject(inputs(), &MapSet.member?(done, &1.input_id))
  end

  @doc """
  Runs a tool over one input at the version it described, and records what it
  measured, or why it could not.

  A response carrying a positional vector, or a schema version the deployment
  does not know, is refused and recorded. A permanent failure is recorded. A
  transient failure is returned for the caller to retry.
  """
  @spec analyse(module(), input(), map()) ::
          {:ok, Derivation.t()} | :refused | :failed | {:error, :transient, term()}
  def analyse(tool, input, %{name: name, version: version}) do
    master = Normalize.master_of(input.source_id, input.part_sequence)
    request = request(master, input)

    case tool.analyse(request) do
      {:ok, response} ->
        case accept(response) do
          {:ok, measurements} ->
            record(name, version, input, master, measurements)

          {:refused, reason} ->
            fail(name, version, input, "response_refused", true, reason, :refused)
        end

      {:error, :permanent, reason} ->
        fail(name, version, input, "analysis_failed", true, reason, :failed)

      {:error, :transient, reason} ->
        {:error, :transient, reason}
    end
  end

  @doc """
  Records that a transient failure was retried until the retries ran out.
  """
  @spec exhausted(map(), input(), term()) :: :failed
  def exhausted(%{name: name, version: version}, input, reason),
    do: fail(name, version, input, "transient_failure_exhausted", false, reason, :failed)

  @doc """
  Records that a tool raised on its last attempt at an input.
  """
  @spec crashed(map(), input(), String.t()) :: :failed
  def crashed(%{name: name, version: version}, input, message),
    do: fail(name, version, input, "crashed", false, message, :failed)

  @doc """
  What a tool response must be: a known schema version and measurements by
  name, each a number or a string. A list anywhere is a positional vector, whose
  meaning depends on an order the response does not carry, and is refused.
  """
  @spec accept(map()) :: {:ok, map()} | {:refused, term()}
  def accept(%{"schema_version" => schema_version, "measurements" => measurements})
      when is_map(measurements) do
    unnamed =
      for {name, value} <- measurements, not (is_number(value) or is_binary(value)), do: name

    cond do
      schema_version not in config(:schema_versions) ->
        {:refused, %{unknown_schema_version: schema_version}}

      unnamed != [] ->
        {:refused, %{not_a_named_value: unnamed}}

      true ->
        {:ok, measurements}
    end
  end

  def accept(response), do: {:refused, %{malformed: Map.keys(response)}}

  @doc """
  The request a tool receives for an input: the master's bytes and, for one
  stream, that stream's index in the master as it now stands. The index is
  looked up by the stream's identity each time, since the master may order its
  streams differently from the file that was acquired.
  """
  @spec request(Pluteus.Catalog.Asset.t(), input()) :: map()
  def request(master, input) do
    %{
      path: Storage.path(master.location),
      stream_index: stream_index(master, input.stream),
      start_ms: input.start_ms,
      end_ms: input.end_ms
    }
  end

  defp stream_index(_master, nil), do: nil

  defp stream_index(master, selector) do
    {:ok, probe} = Probe.probe(master.location)

    case stream_index_in(probe, selector) do
      nil -> raise "no stream in #{master.location} is #{inspect(selector)}"
      index -> index
    end
  end

  @doc """
  The index in a probed file of the stream a `track` selector names, or nil.
  Streams that carry no content — cover art, data, timecode, attachments — are
  passed over, since no selector names one, but they still count towards the
  indices of the streams after them.
  """
  @spec stream_index_in(map(), map()) :: non_neg_integer() | nil
  def stream_index_in(probe, selector) do
    content =
      probe
      |> Identify.streams()
      |> Enum.with_index()
      |> Enum.filter(fn {stream, _index} -> stream["content"] end)

    selectors = content |> Enum.map(&elem(&1, 0)) |> Streams.track_selectors()

    case Enum.find_index(selectors, &(&1 == selector)) do
      nil -> nil
      position -> content |> Enum.at(position) |> elem(1)
    end
  end

  # The tool has run by now, outside any transaction. Only the recording writes,
  # and it writes as the deployment.
  defp record(name, version, input, master, measurements) do
    result = record_measurements(name, version, input, master, measurements)
    record_undefined(name, version, input, measurements)

    result
  end

  defp record_measurements(name, version, input, master, measurements) do
    Actor.as(Principals.system!().id, fn ->
      {:ok, derivation} =
        Annotations.record_derivation(%{
          tool: name,
          version: version,
          input_id: input.input_id,
          parameters: %{
            "asset" => master.id,
            "start_ms" => input.start_ms,
            "end_ms" => input.end_ms
          },
          derived_at: DateTime.utc_now()
        })

      {:ok, _} =
        Annotations.annotate(%{
          target_id: input.input_id,
          body_type: "measurements",
          body: measurements,
          derivation_id: derivation.id
        })

      {:ok, derivation}
    end)
  end

  # A registry-named field the tool answers for and left unmeasured gets a finding
  # naming that field. spec-10 §5.2 reports *attempted, failed* only where a finding
  # stands, so without one the derivation would make the field read *not yet
  # examined*. Naming the field keeps the tool's other measurements answered.
  #
  # Permanent: the same bytes at the same version measure the same, so there is
  # nothing to retry. Clearing it records that a person has seen it. To say more
  # than "a tool could not", they assert *known unknowable* (spec-02 §6.5), which
  # outranks the finding.
  defp record_undefined(name, version, input, measurements) do
    for field <- undefined(name, input.input_id, measurements) do
      Ingest.record_finding(%{
        stage: :analyse,
        kind: "measurement_undefined",
        permanent: true,
        detail: %{"field" => field},
        input_id: input.input_id,
        tool_version_id: Repo.get_by!(ToolVersion, tool: name, version: version).id
      })
    end
  end

  defp undefined(tool, input_id, measurements) do
    case Lifecycle.state(input_id) do
      {:live, %{kind: kind}} ->
        for descriptor <- FieldRegistry.derived_fields(kind),
            descriptor["derived"]["tool"] == tool,
            not Map.has_key?(measurements, descriptor["derived"]["key"]),
            do: descriptor["name"]

      # Recycled or purged while the tool was running. What it measured is still
      # recorded; nothing further is recorded against a res on its way out.
      {:recycled, _res, _recycling} ->
        []

      {:purged, _res, _tombstone} ->
        []
    end
  end

  defp fail(name, version, input, kind, permanent, reason, outcome) do
    tool_version = Repo.get_by!(ToolVersion, tool: name, version: version)

    Ingest.record_finding(%{
      stage: :analyse,
      kind: kind,
      permanent: permanent,
      detail: %{reason: inspect(reason)},
      input_id: input.input_id,
      tool_version_id: tool_version.id
    })

    outcome
  end

  defp live?(res_id), do: match?({:live, _}, Lifecycle.state(res_id))

  defp config(key), do: :pluteus |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
