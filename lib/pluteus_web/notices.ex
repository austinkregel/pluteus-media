defmodule PluteusWeb.Notices do
  @moduledoc """
  The third-party material vendored into this repository, and what each one's licence
  obliges.

  Annex A.8.1 states the obligation for the glyph set in full: "The copyright notice
  and permission notice MUST travel with the vendored copies and with any glyph derived
  from them. The notice lives beside the vendored files and in the interface's
  third-party notices." Beside the files is `priv/icons/heroicons/LICENSE`; this is the
  other half.

  Only material that is **vendored** is listed. A dependency resolved by the build is
  fetched by whoever builds, and its licence travels in its own package; what is
  committed here is redistributed by this repository and so carries the obligation
  here.

  Each notice is read from the file that states it, at compile time, so it cannot drift
  from the copy it describes and so it survives into a release where `assets/` does
  not. Where a source states no licence, that is recorded as what is known rather than
  filled in from somewhere else.
  """

  alias Pluteus.Design.Icons
  alias Pluteus.Design.Schema

  @heroicons_licence Path.join(Icons.root(), "LICENSE")
  @dtcg Path.join(Schema.root("2025.10"), "SOURCES.json")

  @external_resource @heroicons_licence
  @external_resource @dtcg

  @notices [
    %{
      name: "Heroicons",
      version: Icons.version(),
      source: "https://github.com/tailwindlabs/heroicons",
      vendored: "priv/icons/heroicons",
      what:
        "The glyph set spec-10 Annex A.8.1 names, at the three grids A.8.2's ladder " <>
          "binds to its size bands.",
      licence: File.read!(@heroicons_licence)
    },
    %{
      name: "topbar",
      version: "3.0.0",
      source: "http://buunguyen.github.io/topbar",
      vendored: "assets/vendor/topbar.js",
      what: "The progress bar shown during a live navigation.",
      licence:
        "MIT License\n\nCopyright (c) 2024 Buu Nguyen\n\n" <>
          "The file carries its licence and copyright as a header comment; the full " <>
          "MIT text is the same as the one above."
    },
    %{
      name: "Design Tokens Format Module and Resolver Module",
      version: "2025.10",
      source: "https://www.designtokens.org/",
      vendored: "priv/design/schemas/dtcg/2025.10",
      what:
        "The JSON Schemas A.1.1 pins and requires the token file validate against " <>
          "in continuous integration, vendored so that validation reaches no network.",
      licence:
        "The published schema files carry no licence, copyright or rights statement, " <>
          "and none accompanied them at the URLs recorded in their SOURCES.json. " <>
          "That is stated here as what is known rather than assumed from elsewhere."
    }
  ]

  @doc """
  Every vendored third party, with the notice its own files state.
  """
  @spec all() :: [map()]
  def all, do: @notices
end
