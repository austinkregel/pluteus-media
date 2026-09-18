defmodule PluteusWeb.OnboardingController do
  @moduledoc """
  Claims the one-time onboarding secret (spec-06 §6.5).

  The claimant must already be authenticated through the proxy; the secret is
  the evidence of host access, and the identity is what the first
  Administrator is mapped to. Once any principal exists the route answers as if
  it were not there.
  """

  use PluteusWeb, :controller

  alias Pluteus.Onboarding
  alias PluteusWeb.Problem

  def create(conn, %{"secret" => secret}) do
    case Onboarding.claim(secret, conn.assigns.identity) do
      {:ok, %{administrator: administrator}} ->
        conn |> put_status(201) |> json(%{administrator: administrator.id})

      {:error, :already_onboarded} ->
        Problem.send(conn, 404, %{type: "about:blank", title: "Not Found"})

      {:error, reason} ->
        Problem.send(conn, 403, %{
          type: Problem.type("onboarding-refused"),
          title: "Onboarding refused",
          detail: to_string(reason)
        })
    end
  end
end
