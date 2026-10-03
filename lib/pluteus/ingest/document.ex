defmodule Pluteus.Ingest.Document do
  @moduledoc """
  Reads a metadata document's fields as embedded tags (spec-04 §5, §6.3).

  The document comes from the inbox, so it is hostile input and spec-04 §11 governs it.
  Three properties hold of the reading:

    * nothing the document names is opened, and a document that names anything outside
      itself is refused rather than read. An external entity or an external DTD is a file,
      or a host, of the document's choosing, and the declaration is what says so: a
      document that reaches for `/etc/passwd` and comes back with nothing has still
      reached, and the person is told which document did it.
    * an entity is not expanded into more than it is. Nested entity definitions multiply,
      so a few hundred bytes can declare gigabytes of text.
    * no tree is built. A flat map of the root's own fields is all §6.3 reads, so a
      document declaring a million elements costs a million events and no records.

  `external_entities` and `entity_recurse_limit` are stated in the options although
  xmerl 2.1.8 already defaults to them, so that the second property is the deployment's
  and not the library version's.

  Three bounds hold together, and each is needed. The caller's byte ceiling bounds the
  document, and with it the expansion: twenty thousand references to a fifty-byte entity
  is a million characters from sixty kilobytes, which no limit on nesting refuses.
  `@recurse_limit` bounds the nesting, which is the multiplication. And the parse runs
  under a deadline, because a declaration can be refused quickly or slowly and the stage
  must not wait on which.
  There is no schema and no field vocabulary. A field is whatever the document's root
  carries, named as the document names it, and §6.3 decides what any of it means. A
  document whose root carries structure rather than a value contributes nothing, since a
  tag is a value.
  """

  # One entity naming another is a document a person could write, and no metadata format
  # this registry names uses even that. Nesting beyond this is multiplication, and xmerl
  # refuses it at this depth while the expansion is still small enough to refuse quickly.
  @recurse_limit 2

  # Long enough for the largest document the byte ceiling admits, which expands in a
  # fraction of a second, and short enough that the stage is never held.
  @deadline 5_000

  @typedoc """
  Why a document could not be read: it named a resource outside itself, naming which, or
  it would not parse. A parser's complaint is recorded rather than interpreted, because
  what is wrong with a hostile document is not a vocabulary this deployment can close.
  """
  @type refusal ::
          {:names_outside_itself, [String.t()]}
          | {:unparseable, String.t()}
          | {:timed_out, pos_integer()}

  @doc """
  The fields a document's root carries, keyed as `Pluteus.Ingest.Streams.tags/1` keys a
  container's: folded to lower case and NFC, so a document and a container that name the
  same field name it the same way.

  A field appearing more than once keeps the first, which is the one a reader of the
  document would see first.
  """
  @spec fields(binary()) :: {:ok, %{optional(String.t()) => String.t()}} | {:error, refusal()}
  def fields(bytes) when is_binary(bytes) do
    task = Task.async(fn -> parse(bytes) end)

    case Task.yield(task, @deadline) || Task.shutdown(task, :brutal_kill) do
      {:ok, answer} -> answer
      nil -> {:error, {:timed_out, @deadline}}
    end
  end

  defp parse(bytes) do
    options = [
      {:event_fun, &accumulate/3},
      {:event_state, %{depth: 0, field: nil, text: [], fields: %{}, outside: []}},
      {:external_entities, :none},
      {:entity_recurse_limit, @recurse_limit}
    ]

    case :xmerl_sax_parser.stream(bytes, options) do
      {:ok, %{outside: [_named | _more] = named}, _trailing} ->
        {:error, {:names_outside_itself, Enum.reverse(named)}}

      {:ok, %{fields: fields}, _trailing} ->
        {:ok, fields}

      refused ->
        {:error, {:unparseable, refused |> inspect() |> String.slice(0, 500)}}
    end
  end

  # A declared external entity, and a doctype naming a system identifier, each name
  # something the document does not contain. Neither is resolved, and the identifier is
  # kept so that the refusal says what the document went looking for.
  defp accumulate({:externalEntityDecl, _name, _public, system}, _location, state),
    do: %{state | outside: [to_string(system) | state.outside]}

  defp accumulate({:startDTD, _name, _public, system}, _location, state) when system != [],
    do: %{state | outside: [to_string(system) | state.outside]}

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
