defmodule Pluteus.Continuity.Registry do
  @moduledoc """
  The continuity values spec-10 §20 holds: per category the regime, the floor,
  the ceiling and the minimum length below which no position is kept; the
  reporting interval §13.3's idle rule is measured against; how far a resume may
  move backwards before it must be stated; and how long a shared surface waits
  before returning to the choice of principal.

  **The floor and ceiling are proportions for short media and absolute
  quantities for long ones** (spec-10 §13.2), because a proportion of a long work
  is not a small amount: five per cent of a nine-hundred-page novel is forty-five
  pages, which is a real resume. An absolute ceiling is expressed as the time
  remaining, since "three minutes of credits left" is the fact.
  """

  alias Pluteus.Registry

  @source "continuity"

  @doc """
  The thresholds for a category: the regime and its values.

  A category whose regime is `"none"` keeps no position — a photograph is looked
  at rather than got part way through. A category the registry does not name
  raises, rather than being treated as one that keeps a position.
  """
  @spec resume_threshold(String.t()) :: map()
  def resume_threshold(category), do: Map.fetch!(fetch("resume_thresholds"), category)

  @doc """
  Whether a category keeps a resume position at all.
  """
  @spec keeps_position?(String.t()) :: boolean()
  def keeps_position?(category), do: resume_threshold(category)["regime"] != "none"

  @doc """
  Every category the registry holds thresholds for.
  """
  @spec categories() :: [String.t()]
  def categories, do: Map.keys(fetch("resume_thresholds"))

  @doc """
  The heartbeat a reporting session keeps, in milliseconds.

  spec-10 §13.3 measures its idle rule against this directly: a live report from
  a session that has been silent longer than one interval is ignored. There is no
  grace multiplier — a second, hidden threshold is harder to reason about than
  raising this one.
  """
  @spec reporting_interval_ms() :: pos_integer()
  def reporting_interval_ms, do: fetch("reporting_interval_ms")

  @doc """
  How far a resume may move a position backwards, in the medium's own unit,
  before spec-10 §13.3 requires the surface say so rather than jump silently.
  """
  @spec backwards_threshold(String.t() | atom()) :: number()
  def backwards_threshold(unit),
    do: Map.fetch!(fetch("backwards_threshold"), to_string(unit))

  @doc """
  How long a shared surface waits with no input before returning to the choice of
  principal (spec-10 §14.2).
  """
  @spec inactivity_period_ms() :: pos_integer()
  def inactivity_period_ms, do: fetch("inactivity_period_ms")

  @doc """
  How long [spec-10] §12.4's end-of-item offer stands before it acts.

  §12.4 requires the offer "carry a visible interval before it acts" and states no
  figure, and §20 names no registry for it. It is here because it is a continuity
  quantity measured in the same unit as the reporting interval beside it, and because a
  figure in code is one a deployment could not change without a release.
  """
  @spec next_member_offer_ms() :: pos_integer()
  def next_member_offer_ms, do: fetch("next_member_offer_ms")

  defp fetch(key), do: Map.fetch!(registry(), key)

  defp registry, do: Registry.read(@source)
end
