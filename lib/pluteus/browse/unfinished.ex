defmodule Pluteus.Browse.Unfinished do
  @moduledoc """
  The gateway's Unfinished band: four doors into work the household has not finished
  Each is a door rather than a report, so each carries what it would open onto. Three
  count catalogue and derivation facts. The fourth counts nothing, and that is the whole
  of what makes it lawful.

  ## Why one of them carries no number

  No surface may be composed from more than one principal's consumption, at any
  granularity. "How many holdings nobody here has looked at" is exactly such a total, so
  it cannot be shown to anyone.

  What replaces it is the requesting principal's own looking, which is theirs to see. Even
  so no figure is reported: a number would be the first thing on the surface a person
  could compare against another person's, and the door works without it. So this answers
  whether there is anything behind it and nothing more.

  ## What the other three are

  *Unverified* is an integrity obligation falling due — an asset whose bytes have not
  been read back inside its own interval. The overdue predicate is
  `Pluteus.Assets.unverified_query/1`'s and is not restated here, because a surface that
  disagreed with the pass doing the work would be worse than one that said nothing.

  *No date recorded* is a holding whose container stated no date its form fixed. Such a
  date stays unexamined until a person says otherwise rather than being guessed at, which
  is what makes it a door worth opening.

  *Needs a decision* is the open candidates: a pair something raised as possibly one
  thing, which only a member can settle.
  """

  import Ecto.Query

  alias Pluteus.Assets
  alias Pluteus.Browse.Entries
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Refinements
  alias Pluteus.Dedup.Candidate
  alias Pluteus.Events.Event
  alias Pluteus.Repo

  @typedoc """
  A door: what it is, and either how many holdings are behind it or that there are some.
  A count of `nil` is not an unknown figure — it is a door that reports none.
  """
  @type door :: %{bucket: String.t(), count: non_neg_integer() | nil, any?: boolean()}

  @doc """
  The four doors, for the principal asking.
  """
  @spec for_principal(Ecto.UUID.t()) :: [door()]
  def for_principal(principal_id) do
    [
      unexamined_by(principal_id),
      counted("unverified", unverified()),
      counted("no_date_recorded", undated()),
      counted("needs_a_decision", undecided())
    ]
  end

  defp counted(bucket, count), do: %{bucket: bucket, count: count, any?: count > 0}

  # Reported as a door with something behind it or nothing, never as a figure.
  #
  # An event names the res a person acted on — a digital item, a track — and a browse
  # entry is a work, so what the principal has looked at is reached through the works
  # their own events name. That mapping is over this principal's history alone, which is
  # what keeps the question theirs.
  defp unexamined_by(principal_id) do
    looked_at =
      principal_id
      |> looked_at_res()
      |> Catalog.works_of_many()
      |> Map.values()
      |> Enum.uniq()

    %{
      bucket: "nothing_you_have_looked_at",
      count: nil,
      any?: Repo.exists?(from [work: w] in Entries.base(), where: w.id not in ^looked_at)
    }
  end

  defp looked_at_res(principal_id) do
    Repo.all(
      from e in Event,
        where: e.principal_id == ^principal_id,
        distinct: true,
        select: e.res_id
    )
  end

  # The integrity obligation, counted over the holdings it falls due on rather than
  # over the assets: a holding realized by six parts is one thing to attend to, and a
  # band whose numbers counted different kinds of thing would not be a band.
  defp unverified do
    overdue = from a in Assets.unverified_query(), select: a.digital_item_id

    Repo.aggregate(
      from(i in DigitalItem, where: i.id in subquery(overdue), distinct: true, select: i.id),
      :count
    )
  end

  # A date is recorded against the manifestation that was issued, so a holding is undated
  # where nothing it embodies carries the relation.
  defp undated do
    refinement = Refinements.name!("time-of-publication-or-manufacture")

    dated = from a in Association, where: a.refinement == ^refinement, select: a.subject_id

    Repo.aggregate(
      from([work: w] in Entries.base(),
        where: not exists(embodies_one_of(dated)),
        select: w.id
      ),
      :count
    )
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
    Repo.aggregate(from(c in Candidate, where: is_nil(c.decision), select: c.left_id), :count)
  end
end
