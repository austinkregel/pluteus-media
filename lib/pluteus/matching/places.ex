defmodule Pluteus.Matching.Places do
  @moduledoc """
  What a photograph's coordinate supports, given the populated places near it (spec-05
  §9.7, criterion 39).

  **A coordinate is not a place name.** The gazetteer answers with the nearest places and
  how far each is, which is a resemblance. The answer is recorded at the granularity the
  evidence supports and the next finer place is raised as a candidate:

  | Evidence | Recorded | Candidate |
  | --- | --- | --- |
  | a stated accuracy within the locality bound, and a place near enough | that locality | — |
  | the neighbours agree on a first-order division | that division | the nearest locality, if near enough |
  | the neighbours agree only on a country | that country | the nearest place's division |
  | the neighbours span countries | nothing | the nearest place's country |
  | no place near enough to say anything | nothing | nothing |

  A coordinate with no stated accuracy never supports a locality, however near a place is:
  the device has not said how far from the point the photograph may have been taken.

  The thresholds are the registry's (`Pluteus.Matching.Registry.reverse_geocoding!/1`), and
  the places are references the gazetteer gives — a geonameid, or a division's or
  country's codes — which the caller resolves to the gazetteer's names.
  """

  alias Pluteus.Corpus.Gazetteer
  alias Pluteus.Exif

  @typedoc "A place by the codes that name it, at the granularity it was decided at."
  @type place ::
          {:locality, Gazetteer.neighbour()}
          | {:region, %{country_code: String.t(), admin1_code: String.t()}}
          | {:country, %{country_code: String.t()}}

  @typedoc "What a coordinate supports: the place recorded, and the finer one raised."
  @type answer :: %{recorded: place() | nil, candidate: place() | nil}

  @doc """
  What `position` supports, given `neighbours` nearest first and the registry's
  thresholds.
  """
  @spec answer(Exif.position(), [Gazetteer.neighbour()], %{
          locality_accuracy_metres: number(),
          locality_within_metres: number()
        }) :: answer()
  def answer(_position, [], _thresholds), do: %{recorded: nil, candidate: nil}

  def answer(position, [nearest | _] = neighbours, thresholds) do
    near_enough = nearest.metres <= thresholds.locality_within_metres

    cond do
      precise?(position, thresholds) and near_enough ->
        %{recorded: {:locality, nearest}, candidate: nil}

      region = shared_region(neighbours) ->
        %{recorded: region, candidate: if(near_enough, do: {:locality, nearest})}

      country = shared_country(neighbours) ->
        %{recorded: country, candidate: region_of(nearest)}

      true ->
        %{recorded: nil, candidate: country_of(nearest)}
    end
  end

  defp precise?(%{accuracy: nil}, _thresholds), do: false

  defp precise?(%{accuracy: metres}, %{locality_accuracy_metres: bound}),
    do: metres <= bound

  defp shared_region(neighbours) do
    case neighbours |> Enum.map(&{&1.country_code, &1.admin1_code}) |> Enum.uniq() do
      [{country, admin1}] when is_binary(country) and is_binary(admin1) ->
        {:region, %{country_code: country, admin1_code: admin1}}

      _not_one ->
        nil
    end
  end

  defp shared_country(neighbours) do
    case neighbours |> Enum.map(& &1.country_code) |> Enum.uniq() do
      [country] when is_binary(country) -> {:country, %{country_code: country}}
      _not_one -> nil
    end
  end

  defp region_of(%{country_code: country, admin1_code: admin1})
       when is_binary(country) and is_binary(admin1),
       do: {:region, %{country_code: country, admin1_code: admin1}}

  defp region_of(_without_one), do: nil

  defp country_of(%{country_code: country}) when is_binary(country),
    do: {:country, %{country_code: country}}

  defp country_of(_without_one), do: nil
end
