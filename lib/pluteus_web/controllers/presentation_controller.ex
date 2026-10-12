defmodule PluteusWeb.PresentationController do
  @moduledoc """
  A derived artefact, asked for by profile name ([spec-10] §11.1).

  **The absence of a presentation asset is never an error** (§11.6, §16). Both
  absences are answered in the 2xx range, so that holds on the wire and not only in
  prose: an artefact that can be generated is `202` with the job queued, and one
  with nothing to generate from is `204`. A client that treated either as a failure
  would be reading a status code, not a story the deployment tells about itself.

  The order refusals are taken in is deliberate:

  1. **A dimension parameter is refused first**, before the profile is even looked
     up, so `?width=700` on a profile that exists is refused rather than quietly
     served at the profile's own width. §11.1 forbids arbitrary dimensions because
     an endpoint accepting them is an unbounded transcoder addressable by anyone
     who can write a query string, and a refusal that depends on the profile being
     wrong would leave the hole open for every profile that is right.
  2. **An unknown profile is `400`**, not `404`. The closed set is part of the
     request's grammar, so a name outside it is a malformed request whatever res it
     names.
  3. **Recycled and purged are `410`**, as `PluteusWeb.ContentController` answers
     them, because the subject's lifecycle outranks anything about derivatives.
  4. **A profile the subject cannot have is `404`.** A waveform of a photograph is
     not missing; it does not exist.
  """

  use PluteusWeb, :controller

  alias Pluteus.Catalog.Res
  alias Pluteus.Lifecycle
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Asset
  alias Pluteus.Presentation.Registry
  alias Pluteus.Workers.GeneratePresentationAsset
  alias PluteusWeb.Native
  alias PluteusWeb.Problem
  alias PluteusWeb.StoredBytes

  # Every spelling of "give me this many pixels". The list is closed, because a
  # refusal of unknown parameters generally would also refuse the ones spec-01 §9.1
  # puts in a deep link.
  @dimensions ~w(width height size w h scale)

  def show(conn, %{"id" => id, "profile" => profile} = params) do
    # §9.1 fixes the kind by the path, so an identifier belonging to another kind is
    # not found here rather than answered for.
    kind = conn.assigns.kind

    with :ok <- no_dimensions(params),
         {:ok, declared} <- known_profile(profile),
         {:ok, ordinal} <- page(params),
         {:ok, uuid} <- identifier(id),
         {:live, %Res{kind: ^kind}} <- Lifecycle.state(uuid),
         true <- Presentation.applies?(declared, uuid) do
      answer(conn, uuid, declared, ordinal)
    else
      {:refused, detail} ->
        Problem.send(
          conn,
          400,
          Map.merge(
            %{type: Problem.type("dimension-refused"), title: "dimension refused"},
            detail
          )
        )

      {:recycled, %Res{kind: ^kind}, recycling} ->
        gone(conn, "recycled", %{restorable_until: DateTime.to_iso8601(recycling.purge_after)})

      {:purged, %Res{kind: ^kind}, tombstone} ->
        gone(conn, "purged", %{purged_at: DateTime.to_iso8601(tombstone.purged_at)})

      _absent_or_inapplicable ->
        Native.not_found(conn)
    end
  end

  # §11.1. A dimension is refused whatever profile it accompanies, and the refusal
  # names the closed set so a client can correct itself in one step.
  defp no_dimensions(params) do
    case Enum.filter(@dimensions, &Map.has_key?(params, &1)) do
      [] ->
        :ok

      named ->
        {:refused,
         %{
           detail:
             "a presentation asset is asked for by profile name, never by dimension: " <>
               "#{Enum.join(named, ", ")} #{were(named)} refused",
           profiles: Registry.profile_names()
         }}
    end
  end

  defp were([_one]), do: "is"
  defp were(_several), do: "are"

  defp known_profile(profile) do
    case Registry.profile(profile) do
      {:ok, declared} ->
        {:ok, declared}

      :error ->
        {:refused,
         %{
           detail: "#{profile} is not a profile this deployment serves",
           profiles: Registry.profile_names()
         }}
    end
  end

  defp identifier(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> :no_such_res
    end
  end

  # §12.1's page reader asks for page *n* of a container of pages, and a page is part of
  # what identifies the artefact rather than a dimension of it: §11.1's prohibition is on
  # asking for a size, and this asks which of the holding's pages. A path segment rather
  # than a parameter, because the three columns that identify an artefact are the
  # subject, the profile and the ordinal, and this is the third of them.
  defp page(%{"page" => page}) do
    case Integer.parse(page) do
      {ordinal, ""} when ordinal >= 0 ->
        {:ok, ordinal}

      _not_a_page ->
        {:refused,
         %{
           detail: "#{page} is not a page: a page is a whole number from zero",
           profiles: Registry.profile_names()
         }}
    end
  end

  defp page(_whole_holding), do: {:ok, 0}

  # Present, absent with a source, absent without one. Nothing else is a state a
  # client can be in here, because a row exists exactly where the bytes do.
  defp answer(conn, subject_id, declared, ordinal) do
    profile = Map.fetch!(declared, "name")

    case Presentation.get(subject_id, profile, ordinal) do
      %Asset{} = held ->
        {:ok, served} = Presentation.serve(held)

        conn
        |> put_resp_header("presentation-profile", profile)
        |> StoredBytes.send_stored(served.location,
          content_type: served.media_type,
          etag: served.digest
        )

      nil ->
        awaited(conn, subject_id, profile, ordinal)
    end
  end

  # 202 queues the work and says so; the job's uniqueness is what keeps a page of
  # tiles asking at once from encoding the same artefact many times. 204 queues
  # nothing, because there is nothing to generate from.
  defp awaited(conn, subject_id, profile, ordinal) do
    conn = put_resp_header(conn, "presentation-profile", profile)

    case Presentation.source_for(subject_id) do
      nil ->
        send_resp(conn, 204, "")

      _source ->
        {:ok, _job} = GeneratePresentationAsset.queue(subject_id, profile, ordinal)
        send_resp(conn, 202, "")
    end
  end

  defp gone(conn, type, fields) do
    Problem.send(conn, 410, Map.merge(%{type: Problem.type(type), title: type}, fields))
  end
end
