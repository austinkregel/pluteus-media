defmodule Pluteus.Analysis.Sidecar do
  @moduledoc """
  The analysing sidecar, spoken to over HTTP (spec-04 §8.2).

  It is a tool like any other: it describes itself and analyses one input per
  request. A 422 is its answer that the input can never be analysed, and is a
  permanent failure. A 5xx, a refused connection or a timeout says nothing
  about the input, and is transient.
  """

  @behaviour Pluteus.Analysis.Tool

  @impl true
  def describe do
    case request(:get, "/describe", nil) do
      {:ok, 200, %{"name" => name, "version" => version, "schema_version" => schema_version}} ->
        {:ok, %{name: name, version: version, schema_version: schema_version}}

      {:ok, status, body} ->
        {:error, :transient, {:unexpected, status, body}}

      {:error, reason} ->
        {:error, :transient, reason}
    end
  end

  @impl true
  def analyse(request) do
    case request(:post, "/analyse", request) do
      {:ok, 200, response} -> {:ok, response}
      {:ok, 422, body} -> {:error, :permanent, body}
      {:ok, status, body} -> {:error, :transient, {status, body}}
      {:error, reason} -> {:error, :transient, reason}
    end
  end

  defp request(method, path, body) do
    url = String.to_charlist(config(:url) <> path)
    options = [timeout: config(:timeout_ms), connect_timeout: 5_000]

    http_request =
      case method do
        :get -> {url, []}
        :post -> {url, [], ~c"application/json", Jason.encode!(body)}
      end

    case :httpc.request(method, http_request, options, body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, response}} ->
        {:ok, status, Jason.decode!(response)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp config(key), do: :pluteus |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
