defmodule PluteusWeb.ClientSocketTest do
  @moduledoc """
  Who may hold the socket and join its topics: spec-07 criteria 1 and 13.
  """

  use Pluteus.DataCase, async: true

  import Phoenix.ChannelTest
  import PluteusWeb.ConnCase, only: [issuer: 0]

  alias Pluteus.Administration
  alias Pluteus.PrincipalFixtures
  alias Pluteus.Principals
  alias PluteusWeb.ClientSocket
  alias PluteusWeb.PrincipalChannel

  @endpoint PluteusWeb.Endpoint
  @subject "ada@example.test"

  describe "1. The socket refuses what did not come through forward authentication" do
    test "no proxy secret, a wrong one, or no identity is refused" do
      config = Application.fetch_env!(:pluteus, PluteusWeb.ForwardAuth)
      secret_header = Keyword.fetch!(config, :secret_header)
      subject_header = Keyword.fetch!(config, :subject_header)

      for headers <- [
            [{subject_header, @subject}],
            [{secret_header, "not-the-secret"}, {subject_header, @subject}],
            [{secret_header, Keyword.fetch!(config, :secret)}]
          ] do
        assert {:error, "unauthenticated"} =
                 connect(ClientSocket, %{}, connect_info: %{x_headers: headers})
      end
    end

    test "a client key is not a credential for it", %{actor: actor} do
      %{key: key} = PrincipalFixtures.a_key(actor.id, "Phone")
      config = Application.fetch_env!(:pluteus, PluteusWeb.ForwardAuth)
      secret = {Keyword.fetch!(config, :secret_header), Keyword.fetch!(config, :secret)}

      assert {:error, "unauthenticated"} =
               connect(ClientSocket, %{"apiKey" => key}, connect_info: %{x_headers: [secret]})
    end

    test "a retired principal is refused" do
      assert {:ok, _socket} = connect_as(@subject)

      principal = Principals.principal_for(issuer(), @subject)
      {:ok, admin} = Principals.create_principal(%{role: "administrator"})
      {:ok, _} = Administration.retire_principal(admin, principal.id)

      assert {:error, "retired"} = connect_as(@subject)
    end
  end

  describe "13. No principal can join another's topic" do
    test "its own topic is joinable, and another's is not" do
      {:ok, socket} = connect_as(@subject)
      principal = Principals.principal_for(issuer(), @subject)
      {:ok, other} = Principals.create_principal(%{role: "member"})

      assert {:ok, _reply, _channel} =
               subscribe_and_join(socket, PrincipalChannel, "principal:#{principal.id}")

      assert {:error, %{reason: "not_permitted"}} =
               subscribe_and_join(socket, PrincipalChannel, "principal:#{other.id}")
    end
  end

  defp connect_as(subject) do
    config = Application.fetch_env!(:pluteus, PluteusWeb.ForwardAuth)

    connect(ClientSocket, %{},
      connect_info: %{
        x_headers: [
          {Keyword.fetch!(config, :secret_header), Keyword.fetch!(config, :secret)},
          {Keyword.fetch!(config, :subject_header), subject}
        ]
      }
    )
  end
end
