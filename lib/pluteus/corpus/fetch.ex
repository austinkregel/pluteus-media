defmodule Pluteus.Corpus.Fetch do
  @moduledoc """
  Downloads one file of a corpus, resuming where an earlier attempt stopped (spec-05 §5.7).

  A corpus file runs from a few hundred megabytes to over a hundred gigabytes, so a
  download that restarted from nothing on every interruption might never finish. What has
  arrived is kept in a `.partial` file beside the destination, and the next attempt asks
  the server for the rest with a `Range` header.

  **Whether the server honoured the range is read from the answer, not assumed.** A `206`
  carrying `Content-Range` from the byte asked for is appended to what is held. A server
  that ignores the range answers `200` with the whole file, and appending that would put a
  second copy after the first, so the partial file is emptied and the body taken from the
  start. A `Content-Range` starting anywhere else is refused, since neither appending nor
  starting over would be the file.

  The body is taken in chunks the caller asks for one at a time and written by this
  module, rather than handed to `:httpc`'s own streaming to a file, whose documentation
  does not say whether it appends.

  The file is complete when the stream ends with as many bytes as the server said there
  were. Only then is it moved to its destination, so a destination file is always a whole
  one. Whether it is the *right* whole one is the caller's to decide against what the
  publisher states, which is why the digests are returned rather than compared here.
  """

  @timeout 60_000

  @typedoc """
  What arrived: its size, and a digest per algorithm the caller asked for.
  """
  @type arrived :: %{size: non_neg_integer(), digests: %{atom() => String.t()}}

  @typedoc """
  Why a fetch stopped. What arrived before it stopped is kept, so the next attempt resumes.
  """
  @type stopped ::
          {:status, pos_integer()}
          | {:range_not_honoured, String.t()}
          | {:short, expected: non_neg_integer(), got: non_neg_integer()}
          | :timeout
          | {:transport, term()}

  @doc """
  Fetches `url` to `destination`, resuming a partial download where one is held.

  Options:

    * `:user_agent` — required; how the deployment names itself to the publisher.
    * `:digests` — the algorithms to digest the whole file with, such as `[:sha256]` or
      `[:md5]`, whichever the publisher states its checksums in.
  """
  @spec file(String.t(), Path.t(), keyword()) :: {:ok, arrived()} | {:error, stopped()}
  def file(url, destination, options) do
    user_agent = Keyword.fetch!(options, :user_agent)
    algorithms = Keyword.get(options, :digests, [])
    partial = destination <> ".partial"

    File.mkdir_p!(Path.dirname(destination))

    held = held(partial)
    headers = [{~c"user-agent", String.to_charlist(user_agent)} | range(held)]

    {:ok, request} =
      :httpc.request(
        :get,
        {String.to_charlist(url), headers},
        http_options(url),
        sync: false,
        stream: {:self, :once},
        body_format: :binary
      )

    with :ok <- receive_body(request, partial, held) do
      File.rename!(partial, destination)
      {:ok, %{size: File.stat!(destination).size, digests: digests(destination, algorithms)}}
    end
  end

  defp held(partial) do
    case File.stat(partial) do
      {:ok, %File.Stat{size: size}} -> size
      {:error, :enoent} -> 0
    end
  end

  defp range(0), do: []
  defp range(held), do: [{~c"range", String.to_charlist("bytes=#{held}-")}]

  defp receive_body(request, partial, held) do
    receive do
      {:http, {^request, :stream_start, headers, stream}} ->
        with {:ok, from, total} <- starting_at(headers, held) do
          write(request, stream, partial, from, total)
        end

      # A complete answer rather than a stream: anything but a 200 or a 206. A range past
      # the end means the partial file is already whole.
      {:http, {^request, {{_version, 416, _reason}, headers, _body}}} ->
        already_whole(headers, held)

      {:http, {^request, {{_version, status, _reason}, _headers, _body}}} ->
        {:error, {:status, status}}

      {:http, {^request, {:error, reason}}} ->
        {:error, {:transport, reason}}
    after
      @timeout ->
        :httpc.cancel_request(request)
        {:error, :timeout}
    end
  end

  # Where the body starts, and how long the whole file is.
  defp starting_at(headers, held) do
    case header(headers, "content-range") do
      nil ->
        # The whole file, whatever was asked for.
        {:ok, 0, whole_length(headers, 0)}

      range ->
        with [_all, from, total] <- Regex.run(~r/^bytes (\d+)-\d+\/(\d+)$/, range),
             ^held <- String.to_integer(from) do
          {:ok, held, String.to_integer(total)}
        else
          _elsewhere -> {:error, {:range_not_honoured, range}}
        end
    end
  end

  defp whole_length(headers, from) do
    case header(headers, "content-length") do
      nil -> nil
      length -> from + String.to_integer(length)
    end
  end

  defp already_whole(headers, held) do
    range = header(headers, "content-range")

    with "bytes */" <> total <- range,
         {^held, ""} <- Integer.parse(total) do
      :ok
    else
      _otherwise -> {:error, {:range_not_honoured, range || "416 with no Content-Range"}}
    end
  end

  # Starting from nothing empties whatever was held; continuing appends to it.
  defp write(request, stream, partial, from, total) do
    file = File.open!(partial, if(from == 0, do: [:write, :binary], else: [:append, :binary]))

    received =
      try do
        :ok = :httpc.stream_next(stream)
        chunks(request, stream, file)
      after
        File.close(file)
      end

    complete(received, partial, total)
  end

  defp chunks(request, stream, file) do
    receive do
      {:http, {^request, :stream, chunk}} ->
        :ok = IO.binwrite(file, chunk)
        :ok = :httpc.stream_next(stream)
        chunks(request, stream, file)

      {:http, {^request, :stream_end, _headers}} ->
        :ok

      {:http, {^request, {:error, reason}}} ->
        {:error, {:transport, reason}}
    after
      @timeout ->
        :httpc.cancel_request(request)
        {:error, :timeout}
    end
  end

  # A server that stated no length has nothing to fall short of; one that did is held to it.
  defp complete({:error, _} = stopped, _partial, _total), do: stopped
  defp complete(:ok, _partial, nil), do: :ok

  defp complete(:ok, partial, total) do
    case File.stat!(partial).size do
      ^total -> :ok
      got -> {:error, {:short, expected: total, got: got}}
    end
  end

  defp header(headers, name) do
    case List.keyfind(headers, String.to_charlist(name), 0) do
      {_name, value} -> to_string(value)
      nil -> nil
    end
  end

  defp digests(path, algorithms) do
    states = Map.new(algorithms, &{&1, :crypto.hash_init(&1)})

    path
    |> File.stream!(1_048_576)
    |> Enum.reduce(states, fn chunk, states ->
      Map.new(states, fn {algorithm, state} -> {algorithm, :crypto.hash_update(state, chunk)} end)
    end)
    |> Map.new(fn {algorithm, state} ->
      {algorithm, state |> :crypto.hash_final() |> Base.encode16(case: :lower)}
    end)
  end

  defp http_options("https" <> _rest) do
    [
      autoredirect: true,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 4,
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    ]
  end

  defp http_options(_plain), do: [autoredirect: true]
end
