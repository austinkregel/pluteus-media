defmodule PluteusWeb.WriteController do
  @moduledoc """
  The native API's writes (spec-07 §4.3). Each goes through the operation the
  deployment's own code uses, attributed to the requesting principal, and adds
  none of its own.
  """

  use PluteusWeb, :controller

  alias Pluteus.Administration
  alias Pluteus.Annotations
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Representative
  alias Pluteus.Catalog.Work
  alias Pluteus.Dedup
  alias Pluteus.Dedup.Candidate
  alias Pluteus.Ingest
  alias Pluteus.Lifecycle
  alias PluteusWeb.Native

  @nomen_fields ~w(
    res_id nomen_string language language_unknown script scheme context_of_use
  )a

  # A request names a level as a string; the atom is looked up in the vocabulary that
  # owns it rather than made from what was sent.
  @decisions Map.new(Candidate.decisions(), &{Atom.to_string(&1), &1})

  {earlier, [last]} = Enum.split(Enum.map(Candidate.decisions(), &Atom.to_string/1), -1)
  @described Enum.join(earlier, ", ") <> " or " <> last

  def create_nomen(conn, params) do
    attrs =
      for field <- @nomen_fields,
          Map.has_key?(params, Atom.to_string(field)),
          into: %{provenance: :local},
          do: {field, Map.fetch!(params, Atom.to_string(field))}

    Native.write(conn, fn -> Catalog.create_nomen(attrs) end, fn conn, nomen ->
      Native.created(conn, %{
        "id" => nomen.id,
        "res_id" => nomen.res_id,
        "nomen_string" => nomen.nomen_string
      })
    end)
  end

  def categorize(conn, %{"id" => id, "scheme" => scheme, "value" => value}) do
    Native.write(conn, fn -> Catalog.correct_category(id, scheme, value) end, fn conn, category ->
      Native.created(conn, Map.take(category, [:res_id, :scheme, :value, :provenance]))
    end)
  end

  def categorize(conn, _params), do: Native.invalid(conn, "a category needs a scheme and a value")

  def annotate(conn, %{"target_id" => target_id, "body_type" => body_type, "body" => body}) do
    attrs = %{
      target_id: target_id,
      body_type: body_type,
      body: body,
      principal_id: conn.assigns.principal.id
    }

    Native.write(conn, fn -> Annotations.annotate(attrs) end, fn conn, annotation ->
      Native.created(conn, %{"id" => annotation.id, "target_id" => annotation.target_id})
    end)
  end

  def annotate(conn, _params),
    do: Native.invalid(conn, "an annotation needs a target_id, body_type and body")

  # spec-01 §6.5's attributes, revised rather than replaced: the attributes named are set,
  # the rest kept, and a null removes the one it names. The work's type bounds which may
  # be named and what values a closed one takes, and a refusal names which.
  def revise_attributes(conn, %{"id" => id, "attributes" => attributes})
      when is_map(attributes) do
    kind = conn.assigns.kind

    Native.write(conn, fn -> Representative.revise(kind, id, attributes) end, fn conn, res ->
      json(conn, %{"id" => res.id, "attributes" => held(res)})
    end)
  end

  def revise_attributes(conn, _params),
    do: Native.invalid(conn, "an attributes write names its attributes as an object")

  defp held(%Work{representative_attributes: attributes}), do: attributes
  defp held(%Expression{significant_attributes: attributes}), do: attributes

  # spec-03 §8.3's member proposal: a pair no signal raised, put forward for a decision.
  def propose(conn, %{"left_id" => left_id, "right_id" => right_id}) do
    principal_id = conn.assigns.principal.id

    Native.write(conn, fn -> Dedup.propose(left_id, right_id, principal_id) end, fn conn, pair ->
      json(conn, %{
        "id" => pair.id,
        "left_id" => pair.left_id,
        "right_id" => pair.right_id,
        "signal" => pair.signal
      })
    end)
  end

  def propose(conn, _params),
    do: Native.invalid(conn, "a proposal names the two res it is about, as left_id and right_id")

  def decide(conn, %{"id" => id, "decision" => decision}) when is_map_key(@decisions, decision) do
    Native.write(
      conn,
      fn -> Dedup.decide(id, Map.fetch!(@decisions, decision), conn.assigns.principal.id) end,
      fn conn, candidate ->
        json(conn, %{"id" => candidate.id, "decision" => candidate.decision})
      end
    )
  end

  def decide(conn, _params), do: Native.invalid(conn, "a decision is #{@described}")

  def restore(conn, %{"id" => id}) do
    Native.write(conn, fn -> Lifecycle.restore(id) end, fn conn, restored ->
      json(conn, %{"restored" => restored})
    end)
  end

  # A principal empties its own deletions; another's is an Administrator's
  # operation, audited (spec-06 §6.1).
  def empty(conn, %{"id" => id}) do
    principal = conn.assigns.principal

    Native.write(
      conn,
      fn ->
        case Lifecycle.empty(id, principal.id) do
          {:error, :not_this_principals_deletion} -> Administration.empty_deletion(principal, id)
          outcome -> outcome
        end
      end,
      fn conn, result -> json(conn, %{"purged" => result.purged}) end
    )
  end

  def clear_finding(conn, %{"id" => id}) do
    Native.write(conn, fn -> Ingest.clear_finding(id, conn.assigns.principal.id) end, fn conn,
                                                                                         finding ->
      json(conn, %{"id" => finding.id, "cleared_at" => finding.cleared_at})
    end)
  end
end
