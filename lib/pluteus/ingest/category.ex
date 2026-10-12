defmodule Pluteus.Ingest.Category do
  @moduledoc """
  What a file is, decided from evidence and from nothing else (spec-04 §6.3).

  Five statements, nearest first, and the first that decides is the answer.

  A file's own container speaks about itself. A document a media manager wrote beside it
  is a record somebody kept about it. Where a household filed it is coarser than either,
  and a recording tagged as a podcast sitting under the television directory is still a
  podcast. Then the format, which is a statement about every file of that format rather
  than about this one: an EPUB is a book. Then the broad class, which decides only where
  it means one kind of thing — software is a game and a package is an archive of pages,
  while video, audio and image each cover several and decide nothing.

  **Where none of them decides, nothing is.** A category nobody stated is not a video of
  a birthday, and recording a guess with the same provenance as a determination leaves
  nothing — not the catalog, not a surface, not a member looking at it — able to tell the
  two apart. The file stays where the household put it until something says what it is,
  which §6.2's correction then outranks the way it outranks any other automatic
  assignment.

  A companion is decided by what it is: §4.6 makes a companion's category its kind, which
  identification has already established from the file itself.

  This runs while the file is still in the inbox, because §4.3 moves it out once the
  deployment takes it and the documents beside it are the evidence.
  """

  alias Pluteus.Ingest.Registry
  alias Pluteus.Ingest.Sidecar
  alias Pluteus.Ingest.Streams

  @typedoc """
  What examination decided: the category, where anything stated one, and everything the
  documents around the file stated, which placement reads after the file has left them.
  """
  @type examined :: %{category: String.t() | nil, container_tags: %{String.t() => String.t()}}

  @doc """
  The category a file's evidence decides, with the fields that evidence carried.

  `identified` is what `Pluteus.Ingest.Identify` read from the bytes; `inbox` and
  `relative` are where the file still lies.
  """
  @spec decide(map(), Path.t(), String.t()) :: examined()
  def decide(%{companion_kind: kind} = _identified, _inbox, _relative) when is_binary(kind),
    do: %{category: Registry.companion_category(kind), container_tags: %{}}

  def decide(identified, inbox, relative) do
    beside = Sidecar.evidence(inbox, relative)
    class = identified.media_class

    %{
      category:
        from_tags(class, Streams.tags(identified.probe)) ||
          from_tags(class, identified.container_tags) ||
          beside.category ||
          filed_as(relative, class) ||
          Registry.category_from_format(identified.format) ||
          Registry.category_from_class(class),
      container_tags: Map.merge(beside.fields, identified.container_tags)
    }
  end

  defp from_tags(class, tags), do: Registry.category_from_tags(class, tags)

  defp filed_as(relative, class) do
    case Registry.path_evidence(relative, class) do
      nil -> nil
      stated -> stated.category
    end
  end
end
