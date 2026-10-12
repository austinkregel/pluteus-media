defmodule Pluteus.Paging do
  @moduledoc """
  A container of pages as the surface that turns them reads it ([spec-10] §12.1).

  A page is an artefact of the holding like any other, identified by the ordinal §11.6
  keys a derivative on, and it is made at each of §20's graded widths so that a browser
  takes the one its own pixels ask for rather than the widest there is (§11.1). Which
  widths are there is therefore what a page consists of here, and the shape they were
  measured at is what §11.2's box is reserved with.

  **An absence is a state and not an error** (§11.6). A page nothing has made yet, one
  whose entry a tool tried to read and could not, and a holding with no bytes to make
  one from are three different facts, and §5.2 is the vocabulary they are reported in.
  """

  alias Pluteus.Ingest
  alias Pluteus.Ingest.Finding
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Geometry
  alias Pluteus.Presentation.Registry

  @typedoc """
  One graded width of a page: what to ask for it by, how wide it came out, and the
  shape it came out in.
  """
  @type width :: %{
          profile: String.t(),
          width: pos_integer(),
          aspect_ratio: float()
        }

  @doc """
  Every width of one page that is held, narrowest first, or the state of its absence.
  """
  @spec open(Ecto.UUID.t(), non_neg_integer()) :: {:shown, [width()]} | {:absent, String.t()}
  def open(subject_id, page) do
    case held(subject_id, page) do
      [] -> {:absent, absence(subject_id, page)}
      widths -> {:shown, widths}
    end
  end

  @doc """
  Asks for the widths of one page that are not held yet.

  Queued rather than made here: extracting an entry from an archive and encoding it
  takes longer than a surface may wait, and the job's uniqueness is what keeps two
  people reading the same issue from encoding one page twice. A holding whose widths
  are all there asks for nothing, and one with no bytes to make them from can ask for
  nothing.

  A page a tool tried and could not read is not asked for again: the same entry at the
  same version gives the same answer, so a person clearing the finding is what says to
  try once more.
  """
  @spec ask(Ecto.UUID.t(), non_neg_integer()) ::
          :held | :queued | :nothing_to_generate | :attempted_failed
  def ask(subject_id, page) do
    made = Presentation.for_ordinal(subject_id, page)

    case Enum.reject(Registry.image_profiles(), &Map.has_key?(made, name!(&1))) do
      [] -> :held
      missing -> asked(subject_id, page, missing)
    end
  end

  @doc """
  The shape to reserve a page's box at: the one a width of it was measured in, and
  §20's figure for the category where none of them has been made (§11.2).

  A page's own shape rather than the holding's, because a holding of pages has no one
  shape: a comic drawn for a screen is far taller than one scanned from paper, and the
  figure §20 names for the category is what stands in until a page says otherwise.
  """
  @spec reserve({:shown, [width()]} | {:absent, String.t()}, String.t() | nil) :: float() | nil
  def reserve({:shown, [%{aspect_ratio: aspect_ratio} | _rest]}, _category), do: aspect_ratio
  def reserve({:absent, _state}, category), do: Geometry.reserve(nil, category)

  defp asked(subject_id, page, missing) do
    if failed?(subject_id, page) do
      :attempted_failed
    else
      answers = for profile <- missing, do: Presentation.ask(subject_id, name!(profile), page)

      if :queued in answers, do: :queued, else: :nothing_to_generate
    end
  end

  # The width each page was measured at rather than the width its profile names, since
  # a profile is a ceiling and a page narrower than it comes out at its own width. Two
  # profiles that capped at the same width are the same picture, so only the narrower of
  # them is offered: a browser given the same image twice would choose between them on
  # a figure that says nothing.
  defp held(subject_id, page) do
    made = Presentation.for_ordinal(subject_id, page)

    Registry.image_profiles()
    |> Enum.map(&made[name!(&1)])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(
      &%{
        profile: &1.profile,
        width: &1.width,
        aspect_ratio: Geometry.ratio(&1.width, &1.height)
      }
    )
    |> Enum.uniq_by(& &1.width)
  end

  # Three absences, in the order the facts settle them. A tool that tried and could not
  # is what a finding records, so it outranks the absence of an artefact; bytes to make
  # the page from mean nobody has made it yet; no bytes at all means the household
  # describes the holding and does not hold it (spec-01 §5.2).
  defp absence(subject_id, page) do
    cond do
      failed?(subject_id, page) -> "attempted_failed"
      Presentation.source_for(subject_id) -> "not_yet_examined"
      true -> "not_held"
    end
  end

  # A finding names the artefact it is about by all three of the columns that identify
  # one, so a page that could not be made ends the asking for that page alone: the next
  # page of the same issue is a different artefact and may be perfectly readable.
  defp failed?(subject_id, page) do
    widths = Enum.map(Registry.image_profiles(), &name!(&1))

    Enum.any?(Ingest.open_findings_for_input(subject_id), fn %Finding{detail: detail} ->
      detail["profile"] in widths and detail["ordinal"] == page
    end)
  end

  defp name!(profile), do: Map.fetch!(profile, "name")
end
