defmodule Pluteus.Design.Schema do
  @moduledoc """
  The vendored JSON Schema for the Design Tokens Format Module (Annex A.1.1).

  A.1.1 requires the token file to validate against the published schema for the
  pinned version with no errors, and requires that validation run in continuous
  integration. Validation here reaches no network: a schema fetched at test time
  would make a green run depend on somebody else's uptime, and a silently changed
  schema would change what the assertion means without anything saying so.

  **The published schema is one bundled file.** `format.json` inlines each of its
  seventeen sibling schemas into `definitions`, keyed by the sibling's URL and
  carrying its own `$id`, so every remote `$ref` resolves from inside the document
  and no resolver hook is needed. The sibling URLs answer 404, which is not a
  defect; they were never meant to be fetched. `mix design.vendor` proves that
  closure when it writes the file, so nothing here has to assume it.

  A.1.1 pins the version exactly, "the format's only stated evolution mechanism
  being a superseding specification", so the version is a literal here and raising
  it is a reviewable commit carrying the new file and its digest.
  """

  @format_version "2025.10"

  @doc """
  The format version Annex A.1.1 pins.
  """
  @spec format_version() :: String.t()
  def format_version, do: @format_version

  @doc """
  Where a version's vendored tree lives.
  """
  @spec root(String.t()) :: Path.t()
  def root(version \\ @format_version) do
    :pluteus |> :code.priv_dir() |> Path.join("design/schemas/dtcg/#{version}")
  end

  @doc """
  What `mix design.vendor` recorded: the base URL, the entry schema, and every
  file with its URL and digest.
  """
  @spec sources() :: map()
  def sources do
    root() |> Path.join("SOURCES.json") |> File.read!() |> Jason.decode!()
  end

  @doc """
  One of the pinned schemas, resolved and ready to validate with.

  `"format"` is the one the token file validates against; `"resolver"` is the
  Resolver Module, which A.1.1 requires contexts be expressed with rather than as
  separate files of separate names.
  """
  @spec resolved(String.t()) :: ExJsonSchema.Schema.Root.t()
  def resolved(entry \\ "format") do
    sources()
    |> Map.fetch!("entries")
    |> Map.fetch!(entry)
    |> read!()
    |> ExJsonSchema.Schema.resolve()
  end

  @doc """
  One vendored file, decoded.
  """
  @spec read!(String.t()) :: map()
  def read!(path) do
    root() |> Path.join(path) |> File.read!() |> Jason.decode!()
  end
end
