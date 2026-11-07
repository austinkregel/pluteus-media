defmodule Pluteus.Matching.Sources do
  @moduledoc """
  A source as the collective agent it is (spec-05 §3.1, criterion 2).

  A corpus is an organization's published data, and a name it supplies is a nomen that
  organization assigned (LRM-R14), so a place GeoNames names is named by GeoNames. The
  agent is made the first time a source supplies anything and found again by the
  registry's name for the source afterwards. Its own name is the one the registry gives,
  in the household's shared vocabulary: the household calls it that.
  """

  alias Pluteus.Catalog
  alias Pluteus.Matching.Registry
  alias Pluteus.Matching.SourceAgent
  alias Pluteus.Repo

  @doc """
  The collective agent a corpus is, made where none is yet.
  """
  @spec agent!(String.t()) :: Ecto.UUID.t()
  def agent!(corpus) do
    case Repo.get(SourceAgent, corpus) do
      %SourceAgent{agent_id: agent_id} ->
        agent_id

      nil ->
        {:ok, %{res: agent}} =
          Catalog.create_named_res(:collective_agent, %{
            nomen_string: Registry.name!(corpus),
            provenance: :automatic
          })

        Repo.insert!(%SourceAgent{source: corpus, agent_id: agent.id})
        agent.id
    end
  end
end
