defmodule PluteusWeb.FindingController do
  @moduledoc """
  What the deployment's stages could not do, or would not guess about
  (spec-04 §9), for a member to see and clear (spec-07 §4.1).
  """

  use PluteusWeb, :controller

  alias Pluteus.Ingest
  alias Pluteus.Ingest.Finding
  alias Pluteus.Repo
  alias PluteusWeb.Native

  @fields [
    :id,
    :stage,
    :kind,
    :permanent,
    :detail,
    :acquisition_id,
    :location,
    :digital_item_id,
    :input_id,
    :tool_version_id,
    :musicbrainz_id,
    :corpus,
    :recorded_at,
    :cleared_at,
    :cleared_by
  ]

  def index(conn, _params),
    do: json(conn, %{"items" => Enum.map(Ingest.open_findings(), &present/1)})

  def show(conn, %{"id" => id}) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Finding{} = finding <- Repo.get(Finding, uuid) do
      json(conn, present(finding))
    else
      _absent -> Native.not_found(conn)
    end
  end

  defp present(finding), do: Map.take(finding, @fields)
end
