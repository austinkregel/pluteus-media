defmodule Pluteus.Ingest.MusicBrainz do
  @moduledoc """
  Asks MusicBrainz what kind of artist an identifier names (spec-04 §6.4).

  A request carries the artist identifier and nothing else, and a User-Agent
  naming this application and the contact the deployment is configured with, as
  MusicBrainz requires. There is no default contact: a deployment configured
  with none makes no request at all.
  """

  @callback artist_type(Ecto.UUID.t()) ::
              {:ok, String.t() | nil} | {:error, :not_found} | {:error, :transient, term()}

  @base "https://musicbrainz.org/ws/2/artist/"

  @doc """
  The contact configured for requests, or nil where there is none.
  """
  @spec contact() :: String.t() | nil
  def contact, do: :pluteus |> Application.fetch_env!(__MODULE__) |> Keyword.get(:contact)

  def artist_type(musicbrainz_id) do
    {:ok, _} = Ecto.UUID.cast(musicbrainz_id)
    agent = String.to_charlist("Pluteus/#{version()} ( #{contact!()} )")
    url = String.to_charlist(@base <> musicbrainz_id <> "?fmt=json")

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 4,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    request = {url, [{~c"user-agent", agent}, {~c"accept", ~c"application/json"}]}
    http_options = [ssl: ssl, timeout: 15_000, connect_timeout: 5_000]

    case :httpc.request(:get, request, http_options, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} -> {:ok, Jason.decode!(body)["type"]}
      {:ok, {{_, 404, _}, _headers, _body}} -> {:error, :not_found}
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, :transient, {:status, status}}
      {:error, reason} -> {:error, :transient, reason}
    end
  end

  defp contact! do
    contact() || raise "no MusicBrainz contact is configured; no request may be made"
  end

  defp version, do: :pluteus |> Application.spec(:vsn) |> to_string()
end
