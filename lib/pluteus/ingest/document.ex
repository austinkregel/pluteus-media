defmodule Pluteus.Ingest.Document do
  @moduledoc """
  Reads a metadata document's fields as embedded tags (spec-04 §5, §6.3).

  The document comes from the inbox, so it is hostile input and spec-04 §11 governs it.
  `Pluteus.Xml` holds what that means for any document from outside; what this adds is
  that **no tree is built**. A flat map of the root's own fields is all §6.3 reads, so a
  document declaring a million elements costs a million events and no records.

  There is no schema and no field vocabulary. A field is whatever the document's root
  carries, named as the document names it, and §6.3 decides what any of it means. A
  document whose root carries structure rather than a value contributes nothing, since a
  tag is a value.
  """

  alias Pluteus.Xml

  @typedoc """
  Why a document could not be read.
  """
  @type refusal :: Xml.refusal()

  @doc """
  The fields a document's root carries, keyed as `Pluteus.Ingest.Streams.tags/1` keys a
  container's: folded to lower case and NFC, so a document and a container that name the
  same field name it the same way.

  A field appearing more than once keeps the first, which is the one a reader of the
  document would see first.
  """
  @spec fields(binary()) :: {:ok, %{optional(String.t()) => String.t()}} | {:error, refusal()}
  def fields(bytes) when is_binary(bytes) do
    case Xml.read(bytes, &accumulate/3, %{depth: 0, field: nil, text: [], fields: %{}}) do
      {:ok, %{fields: fields}} -> {:ok, fields}
      {:error, _refusal} = refused -> refused
    end
  end

  # The root is depth 1 and its own children are depth 2, which are the fields. Anything
  # deeper is structure the root holds rather than a value it states, and opening one
  # abandons the field it sits inside so that a parent holding elements contributes
  # nothing.
  defp accumulate({:startElement, _uri, name, _qname, _attributes}, _location, state) do
    depth = state.depth + 1

    cond do
      depth == 2 -> %{state | depth: depth, field: folded(name), text: []}
      depth > 2 -> %{state | depth: depth, field: nil, text: []}
      true -> %{state | depth: depth}
    end
  end

  defp accumulate({:endElement, _uri, _name, _qname}, _location, state) do
    state = record(state)

    %{state | depth: state.depth - 1, field: nil, text: []}
  end

  defp accumulate({:characters, written}, _location, %{field: field} = state)
       when not is_nil(field),
       do: %{state | text: [to_string(written) | state.text]}

  defp accumulate(_event, _location, state), do: state

  defp record(%{depth: 2, field: field} = state) when not is_nil(field) do
    value = state.text |> Enum.reverse() |> Enum.join() |> String.trim()

    if value == "" or Map.has_key?(state.fields, field),
      do: state,
      else: %{state | fields: Map.put(state.fields, field, normalized(value))}
  end

  defp record(state), do: state

  defp folded(name), do: name |> to_string() |> String.downcase() |> String.normalize(:nfc)

  defp normalized(value), do: String.normalize(value, :nfc)
end
