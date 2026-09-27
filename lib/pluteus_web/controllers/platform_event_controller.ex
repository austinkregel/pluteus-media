defmodule PluteusWeb.PlatformEventController do
  @moduledoc """
  `GET /platform-events` (spec-07 §4.1): what happened to the holdings, which
  spec-01 §11.2 makes visible to the household and spec-06 §6.4 names among the
  three things a member contributes that the household sees by design.

  Every member sees every one of them, including those the System principal
  recorded, so the answer is not scoped by the requesting principal — which is the
  criterion, not an oversight.

  `/platform-events` rather than `/events`: spec-01 §11.3 forbids the two classes
  of §11.2 to share a representation, and a path that reads as covering events in
  general would invite the consumption class into it. There is deliberately no
  route for the consumption class, which each principal reaches only through its
  own surfaces.
  """

  use PluteusWeb, :controller

  alias Pluteus.PlatformEvents
  alias PluteusWeb.Native

  def index(conn, params) do
    case Native.limit(params["limit"]) do
      {:ok, limit} ->
        json(conn, %{"platform_events" => Enum.map(PlatformEvents.all(limit), &of/1)})

      {:error, detail} ->
        Native.invalid(conn, detail)
    end
  end

  defp of(event) do
    %{
      "id" => event.id,
      "type" => event.type,
      "subject" => subject(event),
      "recorded_by" => event.recorded_by,
      "occurred_at" => event.occurred_at
    }
  end

  # Named rather than carried as one of two fields with the other null: spec-01
  # §11.1's "a file arriving" precedes anything catalogued, so `acquired` is about
  # an acquisition and everything after placement is about a res. A client reading
  # the kind knows which resource the identifier belongs to.
  defp subject(%{res_id: nil, acquisition_id: id}), do: %{"kind" => "acquisition", "id" => id}
  defp subject(%{res_id: id}), do: %{"kind" => "res", "id" => id}
end
