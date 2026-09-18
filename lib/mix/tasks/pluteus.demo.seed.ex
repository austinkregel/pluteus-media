defmodule Mix.Tasks.Pluteus.Demo.Seed do
  @shortdoc "Fetches the openly licensed demo corpus and copies it into the inbox"

  @moduledoc """
  Fetches the demo corpus listed in `priv/demo/manifest.json` and copies it into
  the inbox, where the ingest stages take it from there.

  Every file in the corpus is public domain or CC0, from a source whose
  licence was read from its own metadata; the manifest records the source, the
  licence, the credit, and what each file demonstrates. The media are not kept
  in the repository.

  Each file is downloaded once into a cache keyed by its SHA-256, and refused
  unless its bytes match the digest the manifest pins. Files are copied into
  the inbox, not moved, so the cache survives the inbox being emptied by
  acquisition.

  The sources ask automated clients to identify themselves. `--contact` adds a
  way to reach whoever is running the task to the user agent; nothing is sent
  that the option does not supply. A source that answers 429 or 503 with a
  `Retry-After` is waited for, a bounded number of times, and each wait is
  printed; after the last, the task fails.

      mix pluteus.demo.seed
      mix pluteus.demo.seed --inbox /path/to/inbox --cache /path/to/cache
      mix pluteus.demo.seed --contact "https://example.org/contact"
  """

  use Mix.Task

  @attempts 3

  @impl Mix.Task
  def run(args) do
    {options, _rest} =
      OptionParser.parse!(args, strict: [inbox: :string, cache: :string, contact: :string])

    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started([:inets, :ssl])

    inbox = options[:inbox] || Application.fetch_env!(:pluteus, Pluteus.Ingest)[:inbox]
    cache = options[:cache] || Path.expand("tmp/demo-cache", File.cwd!())
    agent = user_agent(options[:contact])
    File.mkdir_p!(cache)

    for entry <- manifest() do
      cached = fetch!(entry, cache, agent)
      target = Path.join(inbox, entry["path"])
      File.mkdir_p!(Path.dirname(target))
      File.cp!(cached, target)
      Mix.shell().info("#{entry["licence"]}  #{entry["path"]}")
    end

    Mix.shell().info("Seeded #{length(manifest())} files into #{inbox}")
  end

  @doc """
  The corpus the manifest lists.
  """
  @spec manifest() :: [map()]
  def manifest do
    :pluteus
    |> :code.priv_dir()
    |> Path.join("demo/manifest.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("entries")
  end

  defp user_agent(nil), do: ~c"pluteus-demo-seed/0.1"
  defp user_agent(contact), do: String.to_charlist("pluteus-demo-seed/0.1 (#{contact})")

  defp fetch!(%{"sha256" => expected, "url" => url, "path" => path}, cache, agent) do
    cached = Path.join(cache, expected)

    if File.exists?(cached) and sha256(cached) == expected do
      cached
    else
      partial = cached <> ".partial"
      download!(url, partial, agent, @attempts)
      got = sha256(partial)

      if got != expected do
        File.rm!(partial)
        Mix.raise("#{path} from #{url} has SHA-256 #{got}, not the #{expected} the manifest pins")
      end

      File.rename!(partial, cached)
      cached
    end
  end

  defp download!(url, destination, agent, attempts_left) do
    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 4,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    request = {String.to_charlist(url), [{~c"user-agent", agent}]}
    options = [stream: String.to_charlist(destination)]

    case :httpc.request(:get, request, [ssl: ssl, autoredirect: true], options) do
      {:ok, :saved_to_file} ->
        :ok

      {:ok, {{_version, status, _reason}, headers, _body}}
      when status in [429, 503] and attempts_left > 1 ->
        wait = retry_after!(url, status, headers)
        Mix.shell().info("#{url} answered #{status}; waiting #{wait}s as it asks")
        Process.sleep(wait * 1000)
        download!(url, destination, agent, attempts_left - 1)

      {:ok, {{_version, status, _reason}, _headers, _body}} ->
        Mix.raise("#{url} answered #{status}")

      {:error, reason} ->
        Mix.raise("#{url} could not be fetched: #{inspect(reason)}")
    end
  end

  # A server that asks to be retried says when. One that does not has not
  # asked, and the failure stands.
  defp retry_after!(url, status, headers) do
    case List.keyfind(headers, ~c"retry-after", 0) do
      {_, value} ->
        case Integer.parse(to_string(value)) do
          {seconds, ""} -> seconds
          _date -> Mix.raise("#{url} answered #{status} with a Retry-After of #{value}")
        end

      nil ->
        Mix.raise("#{url} answered #{status} without saying when to retry")
    end
  end

  defp sha256(path) do
    path
    |> File.stream!(1_048_576)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end
end
