defmodule Pluteus.Matching.Registry do
  @moduledoc """
  spec-05 §15's registries: the external identifier schemes, the corpora the deployment
  holds, and the order of evidence rank it applies.

  **This is the one list of external identifier schemes.** A nomen carrying an identifier
  is written in one of these, and `Pluteus.Surfaces.Registry.nomen_schemes/0` reads them
  from here rather than keeping a list of its own, so a scheme cannot be known to one and
  not the other.

  A scheme names the level it identifies (§4.1), because a match at one level licenses
  conclusions about the levels above it and none about those below (§4.3), and a scheme
  without a level would be an identifier nobody could act on.
  """

  alias Pluteus.Registry

  @source "matching"

  @doc """
  Every external identifier scheme the registry names.
  """
  @spec schemes() :: [String.t()]
  def schemes, do: "schemes" |> section() |> Map.delete("for") |> Map.keys() |> Enum.sort()

  @doc """
  A scheme's name, where the registry holds it, so a writer names a scheme the registry
  vouches for. One it does not hold raises, rather than writing an identifier in a scheme
  nothing can act on.
  """
  @spec scheme!(String.t()) :: String.t()
  def scheme!(name) do
    _entry = scheme(name)
    name
  end

  @doc """
  The entity level a scheme identifies (§4.1).
  """
  @spec level(String.t()) :: String.t()
  def level(scheme), do: scheme |> scheme() |> Map.fetch!("level")

  @doc """
  Whether one res may carry several identifiers of a scheme at one level (§5.4).
  """
  @spec several?(String.t()) :: boolean()
  def several?(scheme), do: scheme |> scheme() |> Map.fetch!("several")

  @doc """
  The check-digit algorithm a scheme's identifiers carry (§4.4), or nil where it has none.
  """
  @spec check(String.t()) :: String.t() | nil
  def check(scheme), do: scheme |> scheme() |> Map.get("check")

  @doc """
  The form a scheme's identifiers take (§4.4), where the phase that reads the scheme has
  recorded it. A scheme no phase reads yet has none, and asking raises.
  """
  @spec syntax!(String.t()) :: :uuid | :isrc | :discid
  def syntax!(scheme) do
    case scheme |> scheme() |> Map.fetch!("syntax") do
      "uuid" -> :uuid
      "isrc" -> :isrc
      "discid" -> :discid
    end
  end

  @doc """
  The levels a scheme may identify.
  """
  @spec levels() :: [String.t()]
  def levels, do: "levels" |> section() |> Map.fetch!("known")

  @doc """
  Every corpus the deployment holds.
  """
  @spec corpora() :: [String.t()]
  def corpora, do: "corpora" |> section() |> Map.delete("for") |> Map.keys() |> Enum.sort()

  @doc """
  The name a corpus's publisher gives it, which is the name its collective agent is
  known by (§3.1). A corpus whose entry gives none has not yet supplied anything to name.
  """
  @spec name!(String.t()) :: String.t()
  def name!(corpus), do: corpus |> corpus() |> Map.fetch!("name")

  @doc """
  How a corpus is credited where its terms oblige it (§6.4): what the household uses it
  for, a link to its publisher, and its licence with a link to the licence.
  """
  @spec attribution!(String.t()) :: %{
          what: String.t(),
          link: String.t(),
          licence: String.t(),
          licence_link: String.t()
        }
  def attribution!(corpus) do
    entry = corpus |> corpus() |> Map.fetch!("attribution")

    %{
      what: Map.fetch!(entry, "what"),
      link: Map.fetch!(entry, "link"),
      licence: Map.fetch!(entry, "licence"),
      licence_link: Map.fetch!(entry, "licence_link")
    }
  end

  @doc """
  The schemes a corpus answers.
  """
  @spec answers(String.t()) :: [String.t()]
  def answers(corpus), do: corpus |> corpus() |> Map.fetch!("answers")

  @doc """
  How a corpus reaches the household (§5.7): fetched, replicated or dropped.
  """
  @spec acquisition(String.t()) :: :fetched | :replicated | :dropped
  def acquisition(corpus) do
    case corpus |> corpus() |> Map.fetch!("acquisition") do
      "fetched" -> :fetched
      "replicated" -> :replicated
      "dropped" -> :dropped
    end
  end

  @doc """
  Whether a corpus's snapshot can advance (§5.6).
  """
  @spec advances?(String.t()) :: boolean()
  def advances?(corpus), do: corpus |> corpus() |> Map.fetch!("advances")

  @doc """
  The terms a corpus's data is published under, as the registry states them.
  """
  @spec terms(String.t()) :: String.t()
  def terms(corpus), do: corpus |> corpus() |> Map.fetch!("terms")

  @doc """
  Where a fetched corpus's files are, which files they are, how each is verified, and what
  states the snapshot's date (§5.7, §15).

  A file is verified by its size against the length announced for it, or by its digest
  against the publisher's checksum file. The date is the last-modified time the files
  agree on, or the name of the directory a pointer file names, where the publisher keeps
  each snapshot in a directory of its own.

  A corpus whose entry gives none of this is not yet acquirable, and asking raises rather
  than guessing at an address.
  """
  @spec fetch!(String.t()) :: %{
          from: String.t(),
          files: [String.t()],
          verified_by: :size | {:sha256, String.t()},
          stated_by: :last_modified | {:pointer, String.t()},
          every_months: pos_integer()
        }
  def fetch!(corpus) do
    entry = corpus |> corpus() |> Map.fetch!("fetch")

    %{
      from: Map.fetch!(entry, "from"),
      files: Map.fetch!(entry, "files"),
      verified_by: verified_by(Map.fetch!(entry, "verified_by"), entry),
      stated_by: stated_by(Map.fetch!(entry, "stated_by"), entry),
      every_months: Map.fetch!(entry, "every_months")
    }
  end

  @doc """
  What is held of a corpus published as a database dump: the schema sequence the held
  tables are written for, and the tables, in the order they are loaded.
  """
  @spec dump!(String.t()) :: %{schema_sequence: pos_integer(), tables: [String.t()]}
  def dump!(corpus) do
    entry = corpus |> corpus() |> Map.fetch!("dump")

    %{
      schema_sequence: Map.fetch!(entry, "schema_sequence"),
      tables: Map.fetch!(entry, "tables")
    }
  end

  @doc """
  How a gazetteer's answer to a coordinate is recorded at the granularity the evidence
  supports (§9.7): the feature codes that may answer, the stated accuracy a locality needs,
  how near it must be, how many neighbours must agree on a region, and how near anything
  must be to say anything at all.
  """
  @spec reverse_geocoding!(String.t()) :: %{
          answering_codes: [String.t()],
          locality_accuracy_metres: number(),
          locality_within_metres: number(),
          agreeing_places: pos_integer(),
          nearby_within_metres: number()
        }
  def reverse_geocoding!(corpus) do
    entry = corpus |> corpus() |> Map.fetch!("reverse_geocoding")

    %{
      answering_codes: Map.fetch!(entry, "answering_codes"),
      locality_accuracy_metres: Map.fetch!(entry, "locality_accuracy_metres"),
      locality_within_metres: Map.fetch!(entry, "locality_within_metres"),
      agreeing_places: Map.fetch!(entry, "agreeing_places"),
      nearby_within_metres: Map.fetch!(entry, "nearby_within_metres")
    }
  end

  defp verified_by("size", _entry), do: :size
  defp verified_by("sha256", entry), do: {:sha256, Map.fetch!(entry, "checksums")}

  defp stated_by("last_modified", _entry), do: :last_modified
  defp stated_by("pointer", entry), do: {:pointer, Map.fetch!(entry, "pointer")}

  @doc """
  The order of evidence rank the deployment applies (§5.3).
  """
  @spec rank_order() :: [String.t()]
  def rank_order, do: "rank_order" |> section() |> Map.fetch!("order")

  defp scheme(scheme), do: "schemes" |> section() |> Map.fetch!(scheme)
  defp corpus(corpus), do: "corpora" |> section() |> Map.fetch!(corpus)

  defp section(key), do: @source |> Registry.read() |> Map.fetch!(key)
end
