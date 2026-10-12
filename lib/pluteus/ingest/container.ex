defmodule Pluteus.Ingest.Container do
  @moduledoc """
  Separates what a container holds into its content and the documents that describe it
  (spec-04 §5.3, criterion 35).

  A metadata document the registry names is not content: it states facts about the
  container, is read at identification as an embedded tag, and is never a holding. A
  document the registry does not name is content, and then the ordinary rule decides
  whether a surface could render it.

  Identification takes the class and the tags from this division and placement counts the
  pages from it. A document the registry names is not a page, so the page count is the
  content's length and not the number of entries.
  """

  alias Pluteus.Archive
  alias Pluteus.Ingest.Document
  alias Pluteus.Ingest.Registry
  alias Pluteus.Storage

  @typedoc """
  A container's entries divided, and the embedded tags its documents state. `documents`
  holds the entry names, so a caller can say which entry decided something.
  """
  @type t :: %{
          content: [String.t()],
          documents: [String.t()],
          tags: %{optional(String.t()) => String.t()}
        }

  @typedoc """
  Why a container could not be read: the archive refused, or a document the registry
  named could not be parsed. A document that claims to describe the container and cannot
  be read is not a condition to carry on past — the entry is named so a person can see
  which one.
  """
  @type refusal :: Archive.refusal() | {:document_unreadable, String.t(), term()}

  @doc """
  What the container holds, divided, with the fields its documents state.
  """
  @spec read(String.t()) :: {:ok, t()} | {:error, refusal()}
  def read(location), do: location |> Storage.path() |> read_file()

  @doc """
  The same, of a container read where it lies rather than at a location: a file still in
  the inbox is not the deployment's yet and has none.
  """
  @spec read_file(Path.t()) :: {:ok, t()} | {:error, refusal()}
  def read_file(path) do
    with {:ok, entries} <- Archive.entries_file(path) do
      divide(path, entries)
    end
  end

  defp divide(path, entries) do
    {candidates, rest} = Enum.split_with(entries, &Registry.container_candidate?/1)

    with {:ok, documents, tags} <- documents(path, candidates) do
      {:ok,
       %{
         content: rest ++ (candidates -- documents),
         documents: documents,
         tags: tags
       }}
    end
  end

  defp documents(path, candidates) do
    Enum.reduce_while(candidates, {:ok, [], %{}}, fn candidate, {:ok, named, tags} ->
      case classify(path, candidate) do
        # Where two documents name one field, the one the container lists first keeps it,
        # which is the same rule `Document.fields/1` applies within one document.
        {:document, fields} ->
          {:cont, {:ok, named ++ [candidate], Map.merge(fields, tags)}}

        :content ->
          {:cont, {:ok, named, tags}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  # The entry is read once and the same bytes answer both questions, since the root
  # element that names it a document is in the bytes that would be parsed anyway.
  defp classify(path, entry) do
    case Archive.read_file(path, entry, Registry.container_document_ceiling()) do
      {:ok, bytes} -> interpret(entry, bytes)
      {:error, refusal} -> {:error, {:document_unreadable, entry, refusal}}
    end
  end

  defp interpret(entry, bytes) do
    if Registry.container_document?(bytes) do
      case Document.fields(bytes) do
        {:ok, fields} -> {:document, fields}
        {:error, refusal} -> {:error, {:document_unreadable, entry, refusal}}
      end
    else
      :content
    end
  end
end
