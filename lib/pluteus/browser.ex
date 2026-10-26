defmodule Pluteus.Browser do
  @moduledoc """
  A browser, driven from here, for looking at what the interface actually renders.

  Development tooling. Nothing supervises it, nothing in the application calls it, and no
  surface depends on it existing.

  ## Why this exists rather than a dead render

  [spec-10] §17.7 names four obligations that "are broken by that mechanism and by nothing
  else, and they are invisible to automated checks and to sighted people using a pointer"
  — the mechanism being the patched live document. A dead render is an automated check, so
  the thing that breaks them is the thing a dead render cannot show. Focus after a patch,
  a live region's second announcement of an unchanged message, and whether a collection
  moves as its images arrive are answerable in a browser and nowhere else.

  The same is true of the ordinary case: a page that renders wrongly, or a navigation that
  crashes and recovers by reloading, leaves a green suite behind it.

  ## What it speaks

  W3C WebDriver, which is HTTP and JSON, to the `chromedriver` the image installs beside
  the browser it drives. That is the whole reason there is no dependency here: `:inets`
  and Jason are already the application's, so a driver library would add a tree to do what
  `request/3` does.

  Every call raises on anything but the status it expects. A browser that did not start, a
  session that was refused and a script that threw are each a thing to be told about
  rather than a nil to carry forward.

  ## What a page needs before it will render

  Two cookies and no headers, which is a property of the development proxy rather than of
  this module. The proxy injects the forward-auth secret into every request it passes and
  reads `pluteus_dev_subject` to decide whose identity to assert, and §4.4 makes the
  surface a declaration the device carries in `pluteus_surface`. So `open/2` sets those
  two and the request that arrives is indistinguishable from a person's.

  A cookie cannot be set for a domain the browser has not visited, so `open/2` loads the
  origin, sets them, and loads the path.
  """

  @driver "chromedriver"
  @port 9515
  @host "http://127.0.0.1:#{@port}"

  @typedoc """
  A running browser and the session open on it.
  """
  @type t :: %{session: String.t(), driver: port()}

  @doc """
  Starts a browser and opens `path` on `origin` as a principal on a declared surface.

  `width` and `height` are the viewport, because what a surface does at 390px is a
  different answer from what it does at 1280 and §9.3's rail becomes a tab bar between
  them.
  """
  @spec open(String.t(), keyword()) :: t()
  def open(url, options \\ []) do
    width = Keyword.get(options, :width, 1280)
    height = Keyword.get(options, :height, 900)
    subject = Keyword.get(options, :subject)
    surface = Keyword.get(options, :surface, "near")

    browser = start(width, height)
    %URI{} = uri = URI.parse(url)

    # The origin first: a cookie belongs to a domain, and a browser showing `about:blank`
    # is on no domain to set one for.
    go(browser, "#{uri.scheme}://#{uri.host}#{port_of(uri)}/notices")

    if surface, do: cookie(browser, "pluteus_surface", surface)
    if subject, do: cookie(browser, "pluteus_dev_subject", subject)

    go(browser, url)

    browser
  end

  @doc """
  Closes the session and stops the driver.

  The driver may have gone already — it exits of its own accord once its last session is
  deleted — so the port is closed only if it is still open. That is not a failure being
  swallowed: it is the thing this asks for having already happened.
  """
  @spec close(t()) :: :ok
  def close(%{session: session, driver: driver}) do
    _ = request(:delete, "/session/#{session}", nil)

    if Port.info(driver), do: Port.close(driver)

    :ok
  end

  @doc """
  Loads a URL and waits for the document to be ready and any LiveView on it to have
  joined.

  **The socket being connected is not the view being joined**, and the difference is the
  whole of whether the page does anything. A click on a patch link made while the view's
  channel is still joining is pushed into a channel that cannot send it, times out, and
  LiveView recovers by reloading the page it is on — so the address does not change, no
  handler runs on the server, and nothing is logged anywhere. It reads exactly like a
  patch link that does nothing, and it is a test that acted too early.

  So this waits for the view, not the socket. A page carrying no LiveView has nothing to
  wait for and says so at once.
  """
  @spec go(t(), String.t()) :: :ok
  def go(%{session: session} = browser, url) do
    request(:post, "/session/#{session}/url", %{url: url})
    await(browser, "return document.readyState === 'complete'")

    await(browser, """
    if (!document.querySelector("[data-phx-main]")) return true;
    if (!window.liveSocket) return false;
    return !!(window.liveSocket.main && window.liveSocket.main.isConnected());
    """)

    :ok
  end

  @doc """
  What the page is drawn as, as PNG bytes.
  """
  @spec picture(t()) :: binary()
  def picture(%{session: session}) do
    request(:get, "/session/#{session}/screenshot", nil)
    |> Base.decode64!(ignore: :whitespace)
  end

  @doc """
  The document as it stands now, which after a patch is not what was first served.
  """
  @spec document(t()) :: String.t()
  def document(%{session: session}), do: request(:get, "/session/#{session}/source", nil)

  @doc """
  Evaluates JavaScript in the page and answers with what it returned.

  The script's own `return` is what comes back, so a measurement is taken in the page
  rather than inferred from its markup — which is the point of driving a browser at all.
  """
  @spec evaluate(t(), String.t(), [term()]) :: term()
  def evaluate(%{session: session}, script, arguments \\ []) do
    request(:post, "/session/#{session}/execute/sync", %{script: script, args: arguments})
  end

  @doc """
  Runs a script at the start of every document the session loads from now on, before any
  of the page's own.

  What a measurement of the page *as it first stood* needs: by the time `go/2` returns the
  document is complete, so its images have arrived and whatever they moved has moved. A
  script installed here records the page before that. It goes through chromedriver's
  passthrough to the DevTools protocol, since WebDriver itself has no such command.
  """
  @spec on_every_document(t(), String.t()) :: :ok
  def on_every_document(%{session: session}, script) do
    request(:post, "/session/#{session}/goog/cdp/execute", %{
      cmd: "Page.addScriptToEvaluateOnNewDocument",
      params: %{source: script}
    })

    :ok
  end

  @doc """
  Clicks the first element a CSS selector names.
  """
  @spec click(t(), String.t()) :: :ok
  def click(%{session: session} = browser, selector) do
    id = element(browser, selector)
    request(:post, "/session/#{session}/element/#{id}/click", %{})
    :ok
  end

  @doc """
  Presses Enter on the first element a CSS selector names, as a keyboard does.

  Not `click/2`: a pointer and a keyboard reach a control by different paths, and what
  happens to focus afterwards is a question about the keyboard's. WebDriver's own
  key-sending focuses the element before it sends the key.
  """
  @spec press(t(), String.t()) :: :ok
  def press(browser, selector), do: type(browser, selector, "")

  @doc """
  Types text into the first element a CSS selector names, as a keyboard does, focusing
  it first. WebDriver's codepoint for Enter (`\\uE007`) in the text presses it.
  """
  @spec type(t(), String.t(), String.t()) :: :ok
  def type(%{session: session} = browser, selector, text) do
    id = element(browser, selector)
    request(:post, "/session/#{session}/element/#{id}/value", %{text: text})
    :ok
  end

  @doc """
  Moves focus to the first element a CSS selector names, as a keyboard would.
  """
  @spec focus(t(), String.t()) :: :ok
  def focus(browser, selector) do
    evaluate(browser, "document.querySelector(arguments[0]).focus()", [selector])
    :ok
  end

  @doc """
  What the document is focusing, as `{tag, id}`.

  §17.7's assertion point: after a patch the answer must be the nearest surviving sibling
  rather than the body, and only the document knows.
  """
  @spec focused(t()) :: {String.t(), String.t()}
  def focused(browser) do
    [tag, id] =
      evaluate(browser, """
      const a = document.activeElement;
      return [a ? a.tagName.toLowerCase() : 'none', a ? (a.id || '') : ''];
      """)

    {tag, id}
  end

  @doc """
  Whether a CSS selector matches anything.
  """
  @spec showing?(t(), String.t()) :: boolean()
  def showing?(browser, selector) do
    evaluate(browser, "return document.querySelector(arguments[0]) !== null", [selector])
  end

  @doc """
  The box a selector's element occupies, in CSS pixels.

  What criterion 28 is actually about: a tile's box before its image arrives and after,
  which is a measurement of the rendered page and not of the style attribute that asked
  for it.
  """
  @spec box(t(), String.t()) :: %{String.t() => number()}
  def box(browser, selector) do
    evaluate(
      browser,
      """
      const e = document.querySelector(arguments[0]);
      if (!e) return null;
      const r = e.getBoundingClientRect();
      return {x: r.x, y: r.y, width: r.width, height: r.height};
      """,
      [selector]
    )
  end

  @doc """
  Waits until a script returns something truthy, or raises saying what it was waiting for.
  """
  @spec await(t(), String.t(), pos_integer()) :: :ok
  def await(browser, script, within \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + within

    waiting(browser, script, deadline, script)
  end

  @doc """
  Waits until a CSS selector matches, which is how a live mount is let to settle.
  """
  @spec await_element(t(), String.t(), pos_integer()) :: :ok
  def await_element(browser, selector, within \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + within

    waiting(
      browser,
      "return document.querySelector(arguments[0]) !== null",
      deadline,
      "the element #{selector}",
      [selector]
    )
  end

  @doc """
  Whatever the page logged, which is where a client-side failure says so.

  Not what the live-reload frame logged. In development Phoenix loads an iframe that
  echoes the whole server log to the console, and that is a different document's — so a
  page that said nothing would report hundreds of messages and the one line worth reading
  would be somewhere among them.
  """
  # The session asks for the browser log in its capabilities, so a driver that does not
  # offer it has not done what it was asked, and that raises rather than reading as a page
  # that said nothing.
  @spec console(t()) :: [String.t()]
  def console(%{session: session}) do
    types = request(:get, "/session/#{session}/se/log/types", nil)

    unless is_list(types) and "browser" in types do
      raise "#{@driver} offers no browser log for this session, though it was asked for " <>
              "one: it answered #{inspect(types)}"
    end

    Enum.reject(logged(session), &echoed?/1)
  end

  defp echoed?(message), do: String.contains?(message, "/phoenix/live_reload/frame")

  @doc """
  Which transport the live socket settled on, or nil where no socket was opened.

  A page on `longpoll` has given up on the WebSocket, and Phoenix remembers that for the
  rest of the browser session — so this is the difference between a surface that patches
  and one that polls, which nothing server-side distinguishes.
  """
  @spec transport(t()) :: String.t() | nil
  def transport(browser) do
    evaluate(browser, """
    if (!window.liveSocket) return null;
    const t = window.liveSocket.socket.transport;
    return t && t.name ? t.name : (window.liveSocket.socket.transportName || null);
    """)
  end

  # chromedriver answers on a port once it has bound it, and there is no signal for that
  # besides asking. The status endpoint is the one call that needs no session.
  defp start(width, height) do
    driver =
      Port.open({:spawn_executable, System.find_executable(@driver)}, [
        :binary,
        :exit_status,
        args: ["--port=#{@port}", "--silent"]
      ])

    ready(driver, System.monotonic_time(:millisecond) + 10_000)

    %{session: session(width, height), driver: driver}
  end

  defp ready(driver, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      Port.close(driver)
      raise "#{@driver} did not answer on port #{@port} within ten seconds"
    end

    case :httpc.request(:get, {~c"#{@host}/status", []}, [{:timeout, 500}], []) do
      {:ok, {{_version, 200, _reason}, _headers, _body}} ->
        :ok

      _not_yet ->
        Process.sleep(100)
        ready(driver, deadline)
    end
  end

  # `--no-sandbox` because the container runs as root and Chromium's own sandbox refuses
  # to initialise under uid 0. The container is the boundary here.
  defp session(width, height) do
    body = %{
      capabilities: %{
        alwaysMatch: %{
          "browserName" => "chrome",
          "goog:chromeOptions" => %{
            "binary" => System.find_executable("chromium"),
            "args" => [
              "--headless=new",
              "--no-sandbox",
              "--disable-gpu",
              "--hide-scrollbars",
              "--force-device-scale-factor=1",
              "--window-size=#{width},#{height}"
            ]
          },
          "goog:loggingPrefs" => %{"browser" => "ALL"}
        }
      }
    }

    request(:post, "/session", body)["sessionId"]
  end

  defp element(%{session: session}, selector) do
    found =
      request(:post, "/session/#{session}/element", %{
        using: "css selector",
        value: selector
      })

    case Map.values(found) do
      [id | _rest] -> id
      [] -> raise "no element answered the selector #{selector}"
    end
  end

  defp logged(session) do
    request(:post, "/session/#{session}/se/log", %{type: "browser"})
    |> Enum.map(& &1["message"])
  end

  defp waiting(browser, script, deadline, what, arguments \\ []) do
    cond do
      evaluate(browser, script, arguments) ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        raise "waited ten seconds for #{what} and it never came"

      true ->
        Process.sleep(50)
        waiting(browser, script, deadline, what, arguments)
    end
  end

  defp port_of(%URI{port: nil}), do: ""
  defp port_of(%URI{scheme: "http", port: 80}), do: ""
  defp port_of(%URI{scheme: "https", port: 443}), do: ""
  defp port_of(%URI{port: port}), do: ":#{port}"

  defp cookie(%{session: session}, name, value) do
    request(:post, "/session/#{session}/cookie", %{
      cookie: %{name: name, value: value, path: "/"}
    })
  end

  # WebDriver wraps every answer in `value`, and reports a failure as a 4xx or 5xx whose
  # body says which error it was. Both are taken apart here so a caller sees what it asked
  # for or an exception naming what went wrong.
  defp request(method, path, body) do
    url = ~c"#{@host}#{path}"
    encoded = body && Jason.encode!(body)

    arguments =
      case method do
        :get -> {url, []}
        :delete -> {url, []}
        :post -> {url, [], ~c"application/json", encoded}
      end

    case :httpc.request(method, arguments, [{:timeout, 60_000}], body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, answered}} when status in 200..299 ->
        Jason.decode!(answered)["value"]

      {:ok, {{_version, _status, _reason}, _headers, answered}} ->
        raise "#{@driver} refused #{method} #{path}: #{refusal(answered)}"

      {:error, reason} ->
        raise "#{@driver} could not be reached for #{method} #{path}: #{inspect(reason)}"
    end
  end

  defp refusal(answered) do
    case Jason.decode(answered) do
      {:ok, %{"value" => %{"message" => message}}} -> message
      _unreadable -> answered
    end
  end
end
