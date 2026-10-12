defmodule Pluteus.Xml do
  @moduledoc """
  Reading XML that came from outside the household (spec-04 §11).

  Every document this reads is a document somebody else wrote — a metadata sidecar from
  the inbox, a publication's own package document — so three properties hold of every
  reading, and the caller gets none of them wrong by having its own parse:

    * nothing the document names is opened, and a document that names anything outside
      itself is refused rather than read. An external entity or an external DTD is a
      file, or a host, of the document's choosing, and the declaration is what says so: a
      document that reaches for `/etc/passwd` and comes back with nothing has still
      reached, and the person is told which document did it.
    * an entity is not expanded into more than it is. Nested entity definitions multiply,
      so a few hundred bytes can declare gigabytes of text.
    * the parse runs under a deadline, because a declaration can be refused quickly or
      slowly and the stage must not wait on which.

  `external_entities` and `entity_recurse_limit` are stated although xmerl 2.1.8 already
  defaults to them, so that the second property is the deployment's and not the library
  version's.

  A fourth bound is the caller's, and is the load-bearing one: the bytes handed in. The
  recursion limit bounds nesting, which is the multiplication, and nothing about nesting
  refuses twenty thousand references to a fifty-byte entity — a million characters from
  sixty kilobytes.

  What is accumulated is the caller's. This holds no opinion about elements, because a
  package document's manifest and a sidecar's fields are not the same shape and a reader
  that served both would be a third shape neither of them wants.
  """

  # One entity naming another is a document a person could write, and no format read
  # here uses even that. Nesting beyond this is multiplication, and xmerl refuses it at
  # this depth while the expansion is still small enough to refuse quickly.
  @recurse_limit 2

  # Long enough for the largest document a caller's ceiling admits, which expands in a
  # fraction of a second, and short enough that no stage is held.
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
  Folds a document's events into the caller's state.

  The event function is called with xmerl's own event, its location and the state, as
  `:xmerl_sax_parser` calls one. The two events that say a document names something
  outside itself never reach it: they are the refusal, and a caller cannot forget to
  answer for what it is never asked about.
  """
  @spec read(binary(), (term(), term(), state -> state), state) ::
          {:ok, state} | {:error, refusal()}
        when state: term()
  def read(bytes, accumulate, state) when is_binary(bytes) and is_function(accumulate, 3) do
    task = Task.async(fn -> parse(bytes, accumulate, state) end)

    case Task.yield(task, @deadline) || Task.shutdown(task, :brutal_kill) do
      {:ok, answer} -> answer
      nil -> {:error, {:timed_out, @deadline}}
    end
  end

  defp parse(bytes, accumulate, state) do
    options = [
      {:event_fun, watching(accumulate)},
      {:event_state, {[], state}},
      {:external_entities, :none},
      {:entity_recurse_limit, @recurse_limit}
    ]

    case :xmerl_sax_parser.stream(bytes, options) do
      {:ok, {[_named | _more] = named, _theirs}, _trailing} ->
        {:error, {:names_outside_itself, Enum.reverse(named)}}

      {:ok, {[], theirs}, _trailing} ->
        {:ok, theirs}

      refused ->
        {:error, {:unparseable, refused |> inspect() |> String.slice(0, 500)}}
    end
  end

  # A declared external entity, and a doctype naming a system identifier, each name
  # something the document does not contain. Neither is resolved, and the identifier is
  # kept so that the refusal says what the document went looking for.
  defp watching(accumulate) do
    fn event, location, {outside, theirs} ->
      case event do
        {:externalEntityDecl, _name, _public, system} ->
          {[to_string(system) | outside], theirs}

        {:startDTD, _name, _public, system} when system != [] ->
          {[to_string(system) | outside], theirs}

        _theirs_to_answer ->
          {outside, accumulate.(event, location, theirs)}
      end
    end
  end
end
