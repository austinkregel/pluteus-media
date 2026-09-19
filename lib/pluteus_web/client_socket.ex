defmodule PluteusWeb.ClientSocket do
  @moduledoc """
  Authenticated as the native API is, because what it relays is the native
  API's (spec-07 §5.2): forward authentication, read from the upgrade
  request's headers. A client key is not a credential here. Phoenix
  hands a socket only the request's `x-` headers, so the proxy's secret and
  identity headers must be named with that prefix; a deployment configured
  otherwise could never authenticate a socket, and is refused at connect
  rather than left refusing every client in silence.
  """

  use Phoenix.Socket

  alias PluteusWeb.ForwardAuth

  channel "catalog", PluteusWeb.CatalogChannel
  channel "principal:*", PluteusWeb.PrincipalChannel

  @impl Phoenix.Socket
  def connect(_params, socket, connect_info) do
    config = Application.fetch_env!(:pluteus, ForwardAuth)

    for key <- [:secret_header, :subject_header],
        not String.starts_with?(Keyword.fetch!(config, key), "x-") do
      raise ArgumentError,
            "#{inspect(ForwardAuth)} #{key} must begin with \"x-\" to reach a socket"
    end

    case ForwardAuth.principal(connect_info.x_headers) do
      {:ok, principal} -> {:ok, assign(socket, :principal_id, principal.id)}
      {:error, type, _detail} -> {:error, type}
    end
  end

  @impl Phoenix.Socket
  def id(_socket), do: nil
end
