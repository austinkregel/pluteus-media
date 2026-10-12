defmodule Pluteus.Reading do
  @moduledoc """
  A publication's text as a surface reads it ([spec-10] §12.1, §11.5).

  §11.5's extracted text is one string, and a reader shows a part of it at a time. What
  divides it is the publication's own pagination as the extractor wrote it: `pdftotext`
  emits a form feed at each page break, so the divisions are the document's pages and
  not a length this deployment chose. §20 holds no page length for text — its seek
  granularities are per unit and the units are milliseconds and pages — so a text
  nobody paginated is one division rather than one cut every so many characters, which
  would put a person on a page the publication does not have.

  The index over the whole publication is computed from those divisions. §11.5's
  position list exists for a client with no text, and a surface holding the text can
  count it: two artefacts answering the same question can disagree, and this one is
  arithmetic over what is being displayed.

  **An absence is a state and not an error** (§11.6). A reading whose text nobody has
  made yet, one whose bytes a tool could not read, and one with no bytes at all are
  three different facts, and §5.2 is the vocabulary they are reported in.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Annotations
  alias Pluteus.Annotations.Annotation
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Asset, as: Bytes
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Finding
  alias Pluteus.Ingest.Registry, as: Formats
  alias Pluteus.Lifecycle.RecycledRes
  alias Pluteus.Lifecycle.Tombstone
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Asset
  alias Pluteus.Repo
  alias Pluteus.Storage
  alias Pluteus.Workers.GeneratePresentationAsset

  @profile "text-extracted"

  @typedoc """
  The text, divided as the publication divides it, with the offset each division begins
  at and the length of the whole. Offsets and length are in characters, which is the
  unit §11.5 indexes a publication in.
  """
  @type reading :: %{
          divisions: [String.t()],
          offsets: [non_neg_integer()],
          characters: non_neg_integer()
        }

  @doc """
  The profile a reading's text is held under.
  """
  @spec profile() :: String.t()
  def profile, do: @profile

  @doc """
  Every copy of a work there is text to read, each named by the format it is held in.

  A copy is a manifestation that embodies the work and holds bytes: spec-03 §8.3 keeps
  an `.epub` and a `.txt` of one book as two copies of it rather than merging them, so
  which one is being read is a thing a person chooses and sees. A recycled or purged
  copy is not one, which is the rule every other surface answers for.

  Named by its format, because that is what distinguishes two copies of one text to
  whoever is choosing: both carry the same words and one of them is the one their
  reader renders.
  """
  @spec copies(Ecto.UUID.t()) :: [%{id: Ecto.UUID.t(), format: String.t()}]
  def copies(work_id) do
    Repo.all(
      from x in Expression,
        join: e in Embodiment,
        on: e.expression_id == x.id,
        join: i in DigitalItem,
        on: i.manifestation_id == e.manifestation_id,
        join: a in Bytes,
        on: a.digital_item_id == i.id,
        where: x.work_id == ^work_id,
        where: e.manifestation_id not in subquery(from b in RecycledRes, select: b.res_id),
        where: e.manifestation_id not in subquery(from t in Tombstone, select: t.res_id),
        group_by: e.manifestation_id,
        order_by: e.manifestation_id,
        select: {e.manifestation_id, min(a.format)}
    )
    |> Enum.map(fn {id, format} -> %{id: id, format: Formats.format_name(format)} end)
  end

  @doc """
  One holding's text, or the state of its absence.
  """
  @spec read(Ecto.UUID.t()) :: {:read, reading()} | {:absent, String.t()}
  def read(subject_id) do
    case Presentation.get(subject_id, @profile) do
      %Asset{} = held -> {:read, divided(Storage.read(held.location))}
      nil -> {:absent, absence(subject_id)}
    end
  end

  @doc """
  Asks for the text to be read out of a holding's bytes.

  Queued rather than done here: reading a four-hundred-page document takes longer than
  a surface may wait, and the job's uniqueness is what keeps two people opening the same
  holding from extracting it twice. A holding with nothing to read from queues nothing,
  which is the 204 the wire answers in the same situation.
  """
  @spec ask(Ecto.UUID.t()) :: :queued | :nothing_to_read
  def ask(subject_id) do
    case Presentation.source_for(subject_id) do
      nil ->
        :nothing_to_read

      _source ->
        {:ok, _job} = GeneratePresentationAsset.queue(subject_id, @profile)
        :queued
    end
  end

  @doc """
  Which division a position in characters falls in.
  """
  @spec division_at(reading(), non_neg_integer()) :: non_neg_integer()
  def division_at(%{offsets: offsets}, position) do
    offsets
    |> Enum.take_while(&(&1 <= position))
    |> length()
    |> Kernel.-(1)
    |> max(0)
  end

  @doc """
  How far through the publication a division begins, as a whole number of per cent.

  A publication of no characters is at its beginning, since there is nowhere else in it
  to be.
  """
  @spec share(reading(), non_neg_integer()) :: non_neg_integer()
  def share(%{characters: 0}, _division), do: 0

  def share(%{offsets: offsets, characters: characters}, division) do
    offsets |> Enum.at(division) |> Kernel.*(100) |> div(characters)
  end

  @doc """
  What people have marked in a reading: the passage, who marked it, and when.

  Authored only. spec-02 §10 makes an authored annotation household-visible, which is
  what lets one person's mark be shown to another; a derived one is a tool's reading of
  the text and belongs to whatever asked for it.
  """
  @spec marks(Ecto.UUID.t()) :: [map()]
  def marks(subject_id) do
    quotes =
      for %Address{selector_type: :text_quote} = address <- Catalog.addresses_of(subject_id),
          into: %{},
          do: {address.id, address}

    for %Annotation{} = annotation <- Annotations.authored_on_many(Map.keys(quotes)) do
      address = Map.fetch!(quotes, annotation.target_id)

      %{
        id: annotation.id,
        passage: address.quote_exact,
        before: address.quote_prefix,
        after: address.quote_suffix,
        principal_id: annotation.principal_id,
        marked_at: annotation.inserted_at
      }
    end
  end

  # Three absences, in the order the facts settle them. A tool that tried and could not
  # is what a finding records, so it outranks the absence of an artefact; bytes to read
  # from mean nobody has looked yet; no bytes at all means the household describes the
  # holding and does not hold it (spec-01 §5.2).
  defp absence(subject_id) do
    cond do
      failed?(subject_id) -> "attempted_failed"
      Presentation.source_for(subject_id) -> "not_yet_examined"
      true -> "not_held"
    end
  end

  defp failed?(subject_id) do
    Enum.any?(
      Ingest.open_findings_for_input(subject_id),
      fn %Finding{detail: detail} -> detail["profile"] == @profile end
    )
  end

  defp divided(text) do
    divisions = String.split(text, "\f")

    {offsets, characters} =
      Enum.map_reduce(divisions, 0, fn division, at ->
        {at, at + String.length(division)}
      end)

    %{divisions: divisions, offsets: offsets, characters: characters}
  end
end
