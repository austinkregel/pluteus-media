defmodule Pluteus.Corpus.FetchTest do
  @moduledoc """
  A corpus file is fetched whole, resumed rather than restarted, and never mistaken for
  whole when it is not (spec-05 §5.7).

  Against a real HTTP server on this host, because what is being tested is what a server
  answers and what the fetch makes of it — honouring a range, ignoring one, answering
  short — and a stand-in for `:httpc` would only test the stand-in.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Corpus.Fetch

  @body :binary.copy("0123456789", 10_000)

  defmodule Server do
    @moduledoc false
    import Plug.Conn

    @body :binary.copy("0123456789", 10_000)

    def init(test), do: test

    def call(conn, test) do
      send(test, {:asked, conn.request_path, get_req_header(conn, "range")})
      serve(conn, conn.request_path, from(conn))
    end

    defp from(conn) do
      case get_req_header(conn, "range") do
        ["bytes=" <> range] -> range |> String.trim_trailing("-") |> String.to_integer()
        [] -> nil
      end
    end

    # Honours a range the way a publisher's server does.
    defp serve(conn, "/whole", nil), do: send_resp(conn, 200, @body)
    defp serve(conn, "/whole", from) when from >= byte_size(@body), do: past_the_end(conn)

    defp serve(conn, "/whole", from) do
      last = byte_size(@body) - 1

      conn
      |> put_resp_header("content-range", "bytes #{from}-#{last}/#{byte_size(@body)}")
      |> send_resp(206, binary_part(@body, from, byte_size(@body) - from))
    end

    # Answers every request with the whole file, whatever range was asked for.
    defp serve(conn, "/ignores-range", _from), do: send_resp(conn, 200, @body)

    # Claims a whole a hundred times longer than what it sends.
    defp serve(conn, "/short", _from) do
      conn
      |> put_resp_header("content-range", "bytes 0-9/#{100 * byte_size(@body)}")
      |> send_resp(206, binary_part(@body, 0, 10))
    end

    # Answers a range starting somewhere other than where it was asked to.
    defp serve(conn, "/elsewhere", _from) do
      conn
      |> put_resp_header("content-range", "bytes 5-9/#{byte_size(@body)}")
      |> send_resp(206, binary_part(@body, 5, 5))
    end

    defp serve(conn, "/missing", _from), do: send_resp(conn, 404, "")

    defp past_the_end(conn) do
      conn
      |> put_resp_header("content-range", "bytes */#{byte_size(@body)}")
      |> send_resp(416, "")
    end
  end

  setup do
    {:ok, server} =
      Bandit.start_link(plug: {Server, self()}, ip: {127, 0, 0, 1}, port: 0, startup_log: false)

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    directory =
      Path.join(Pluteus.Corpus.directory(), "fetch-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf!(directory) end)

    %{origin: "http://127.0.0.1:#{port}", destination: Path.join(directory, "dump.gz")}
  end

  describe "§5.7. A file is fetched whole" do
    test "and its digest is what the caller asked for", %{origin: origin, destination: path} do
      assert {:ok, %{size: size, digests: %{sha256: sha256, md5: md5}}} =
               Fetch.file("#{origin}/whole", path,
                 user_agent: "pluteus-test",
                 digests: [:sha256, :md5]
               )

      assert size == byte_size(@body)
      assert File.read!(path) == @body
      assert sha256 == :sha256 |> :crypto.hash(@body) |> Base.encode16(case: :lower)
      assert md5 == :md5 |> :crypto.hash(@body) |> Base.encode16(case: :lower)
      refute File.exists?(path <> ".partial")
    end
  end

  describe "§5.7. A fetch resumes rather than restarting" do
    test "it asks for the rest of what it holds, and appends it", %{
      origin: origin,
      destination: path
    } do
      held = binary_part(@body, 0, 4_000)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path <> ".partial", held)

      assert {:ok, %{size: size}} =
               Fetch.file("#{origin}/whole", path, user_agent: "pluteus-test")

      assert_received {:asked, "/whole", ["bytes=4000-"]}
      assert size == byte_size(@body)
      assert File.read!(path) == @body
    end

    test "a server that ignores the range is taken from the start, not appended", %{
      origin: origin,
      destination: path
    } do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path <> ".partial", binary_part(@body, 0, 4_000))

      assert {:ok, _arrived} =
               Fetch.file("#{origin}/ignores-range", path, user_agent: "pluteus-test")

      # Appended, the file would be the held part followed by a second whole copy.
      assert File.read!(path) == @body
    end

    test "a partial file already whole is finished, not fetched again", %{
      origin: origin,
      destination: path
    } do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path <> ".partial", @body)

      assert {:ok, %{size: size}} =
               Fetch.file("#{origin}/whole", path, user_agent: "pluteus-test")

      assert size == byte_size(@body)
      assert File.read!(path) == @body
    end
  end

  describe "§5.7. What is not whole is never taken for whole" do
    test "a body shorter than the server said is refused and kept to resume", %{
      origin: origin,
      destination: path
    } do
      assert {:error, {:short, expected: expected, got: 10}} =
               Fetch.file("#{origin}/short", path, user_agent: "pluteus-test")

      assert expected == 100 * byte_size(@body)
      refute File.exists?(path)
      assert File.read!(path <> ".partial") == binary_part(@body, 0, 10)
    end

    test "a range answered from somewhere else is refused", %{origin: origin, destination: path} do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path <> ".partial", binary_part(@body, 0, 10))

      assert {:error, {:range_not_honoured, "bytes 5-9/100000"}} =
               Fetch.file("#{origin}/elsewhere", path, user_agent: "pluteus-test")

      refute File.exists?(path)
    end

    test "a refusal by the server is its status", %{origin: origin, destination: path} do
      assert {:error, {:status, 404}} =
               Fetch.file("#{origin}/missing", path, user_agent: "pluteus-test")

      refute File.exists?(path)
    end
  end
end
