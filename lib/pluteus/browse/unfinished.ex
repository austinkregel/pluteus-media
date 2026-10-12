defmodule Pluteus.Browse.Unfinished do
  @moduledoc """
  The gateway's Unfinished band: five doors into work the household has not finished.
  Each is a door rather than a report, so each carries what it would open onto. Four
  count catalogue and derivation facts. The fifth counts nothing, and that is the whole
  of what makes it lawful.

  ## Why one of them carries no number

  No surface may be composed from more than one principal's consumption, at any
  granularity. "How many holdings nobody here has looked at" is exactly such a total, so
  it cannot be shown to anyone.

  What replaces it is the requesting principal's own looking, which is theirs to see. Even
  so no figure is reported: a number would be the first thing on the surface a person
  could compare against another person's, and the door works without it. So this answers
  whether there is anything behind it and nothing more.

  ## What the other four are

  *Unverified* is an integrity obligation falling due — an asset whose bytes have not
  been read back inside its own interval. The overdue predicate is
  `Pluteus.Assets.unverified_query/1`'s and is not restated here, because a surface that
  disagreed with the pass doing the work would be worse than one that said nothing.

  *No date recorded* is a holding whose container stated no date its form fixed. Such a
  date stays unexamined until a person says otherwise rather than being guessed at, which
  is what makes it a door worth opening.

  *No kind recorded* is a holding nothing has said the kind of. It is the one door the
  rest of the gateway cannot report, because a kind is the only axis whose vocabulary is
  closed: a holding without one carries no value any tile could stand for, so it is in
  the total and in no tile's figure. Counting it here is what keeps the kinds band's
  figures and the total reconcilable.

  *Needs a decision* is the open candidates: a pair something raised as possibly one
  thing, which only a member can settle.

  ## Why the band is one query

  Four of the five ask something of the same set — the holdings the catalog currently
  holds — and deciding what that set is costs more than any of the questions asked of it.
  So they are asked together, as conditions each figure counts under, and the set is
  arrived at once for the band rather than once per door.

  The exception is the pairs awaiting a decision, which are not holdings and so share
  nothing with the rest; it rides along in the same pass because a second round trip
  costs more than the condition does.
  """

  import Ecto.Query

  alias Pluteus.Assets
  alias Pluteus.Browse.Entries
  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Refinements
  alias Pluteus.Catalog.Work
  alias Pluteus.Dedup.Candidate
  alias Pluteus.Events.Event
  alias Pluteus.Repo

  @typedoc """
  A door: what it is, and either how many holdings are behind it or that there are some.
  A count of `nil` is not an unknown figure — it is a door that reports none.
  """
  @type door :: %{bucket: String.t(), count: non_neg_integer() | nil, any?: boolean()}

  @doc """
  The five doors, for the principal asking.
  """
  @spec for_principal(Ecto.UUID.t()) :: [door()]
  def for_principal(principal_id) do
    figures =
      Repo.one(
        from [work: w] in Entries.base(),
          select: %{
            unverified: subquery(unverified()),
            undated: filter(count(w.id), not exists(embodies_one_of(dated()))),
            unkinded: filter(count(w.id), not exists(Entries.records_a_kind())),
            unexamined: filter(count(w.id), w.id not in subquery(looked_at(principal_id))),
            undecided: subquery(undecided())
          }
      )

    [
      %{bucket: "nothing_you_have_looked_at", count: nil, any?: figures.unexamined > 0},
      counted("unverified", figures.unverified),
      counted("no_date_recorded", figures.undated),
      counted("no_kind_recorded", figures.unkinded),
      counted("needs_a_decision", figures.undecided)
    ]
  end

  defp counted(bucket, count), do: %{bucket: bucket, count: count, any?: count > 0}

  # The works this principal has looked at.
  #
  # An event names the res a person acted on — a digital item, a track — and a browse
  # entry is a work, so what they have looked at is the works their own events reach:
  # directly, through an expression, through a manifestation embodying one, or through a
  # digital item carrying that manifestation. Those are `Pluteus.Catalog.works_of_many/1`'s
  # four hops, said as a set rather than as a map — which is the difference that tells
  # where a manifestation embodies expressions of two works. A map answers with one of
  # them because a map holds one value per key; here both were looked at, since the person
  # played the bytes and both works answer for them.
  #
  # Over this principal's history alone, which is what keeps the question theirs.
  defp looked_at(principal_id) do
    events = from e in Event, where: e.principal_id == ^principal_id

    directly = from e in events, join: w in Work, on: w.id == e.res_id, select: %{id: w.id}

    through_expressions =
      from e in events, join: x in Expression, on: x.id == e.res_id, select: %{id: x.work_id}

    through_manifestations =
      from e in events,
        join: m in Embodiment,
        on: m.manifestation_id == e.res_id,
        join: x in Expression,
        on: x.id == m.expression_id,
        select: %{id: x.work_id}

    through_carriers =
      from e in events,
        join: d in DigitalItem,
        on: d.id == e.res_id,
        join: m in Embodiment,
        on: m.manifestation_id == d.manifestation_id,
        join: x in Expression,
        on: x.id == m.expression_id,
        select: %{id: x.work_id}

    directly
    |> union(^through_expressions)
    |> union(^through_manifestations)
    |> union(^through_carriers)
    |> subquery()
    |> select([reached], reached.id)
  end

  # The integrity obligation, over the holdings it falls due on rather than over the
  # assets: a holding realized by six parts is one thing to attend to, and a band whose
  # numbers counted different kinds of thing would not be a band.
  defp unverified do
    overdue = from a in Assets.unverified_query(), select: a.digital_item_id

    from i in DigitalItem,
      where: i.id in subquery(overdue),
      select: count(i.id, :distinct)
  end

  # A date is recorded against the manifestation that was issued, so a holding is undated
  # where nothing it embodies carries the relation.
  defp dated do
    refinement = Refinements.name!("time-of-publication-or-manufacture")

    from a in Association, where: a.refinement == ^refinement, select: a.subject_id
  end

  defp embodies_one_of(manifestations) do
    from x in Expression,
      join: e in Embodiment,
      on: e.expression_id == x.id,
      where: parent_as(:work).id == x.work_id,
      where: e.manifestation_id in subquery(manifestations),
      select: 1
  end

  defp undecided do
    from c in Candidate, where: is_nil(c.decision), select: count(c.left_id)
  end
end
