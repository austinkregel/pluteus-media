defmodule Mix.Tasks.Pluteus.Look do
  @shortdoc "Draws a surface in a browser and writes what it looks like"

  @moduledoc """
  Loads a path in a real browser and writes the picture, the document and anything the
  page logged.

  What it is for: every other way of checking a surface reads the markup the server sent.
  A surface is a live document, so the markup the server sent is the one state nobody
  looks at — and a page that renders wrongly, or whose first live navigation crashes and
  recovers by reloading, leaves every test green.

      mix pluteus.look /everything
      mix pluteus.look /everything --at 390
      mix pluteus.look /works/01a0.../play --as someone@household.test --wait "#transport"
      mix pluteus.look /everything --far

  ## Where it looks

  The development proxy, because a surface reads its identity from a forward
  authenticating proxy and refuses a request that carries none. Inside the compose network
  that is `http://proxy`, which is the same path a browser on the host takes to 4101.
  `--url` overrides the origin for looking at something else.

  ## Options

    * `--at` — the viewport width in CSS pixels. Default 1280. §9.3's rail becomes a tab
      bar below 768, so 390 and 1280 are two different answers and both are worth seeing.
    * `--tall` — the viewport height. Default 900.
    * `--as` — the subject the proxy should assert. Default is the proxy's own.
    * `--far` — declare the far surface (§4.4) instead of the near one.
    * `--wait` — a CSS selector to wait for before drawing, so a live mount settles first.
    * `--out` — where to write. Default `tmp/looks`.
    * `--url` — the origin to load from. Default `http://proxy`.
  """

  use Mix.Task

  alias Pluteus.Browser

  @requirements ["app.config"]

  @switches [
    at: :integer,
    tall: :integer,
    as: :string,
    far: :boolean,
    wait: :string,
    out: :string,
    url: :string
  ]

  @impl Mix.Task
  def run(argv) do
    {options, paths} = OptionParser.parse!(argv, strict: @switches)

    path =
      case paths do
        [path] -> path
        [] -> Mix.raise("name the path to look at, as in: mix pluteus.look /everything")
        many -> Mix.raise("one path at a time, not #{length(many)}: #{Enum.join(many, " ")}")
      end

    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    origin = Keyword.get(options, :url, "http://proxy")
    width = Keyword.get(options, :at, 1280)
    height = Keyword.get(options, :tall, 900)
    into = Keyword.get(options, :out, "tmp/looks")

    browser =
      Browser.open(origin <> path,
        width: width,
        height: height,
        subject: options[:as],
        surface: if(options[:far], do: "far", else: "near")
      )

    try do
      if selector = options[:wait], do: Browser.await_element(browser, selector)

      write(browser, into, name(path, width))
    after
      Browser.close(browser)
    end
  end

  defp write(browser, into, name) do
    File.mkdir_p!(into)

    picture = Path.join(into, "#{name}.png")
    document = Path.join(into, "#{name}.html")

    File.write!(picture, Browser.picture(browser))
    File.write!(document, Browser.document(browser))

    Mix.shell().info("drawn   #{picture}")
    Mix.shell().info("read    #{document}")

    said = Browser.console(browser)

    # A page that logged nothing is worth saying so about: the absence is the finding
    # where a surface was expected to complain and did not.
    if said == [] do
      Mix.shell().info("logged  nothing")
    else
      File.write!(Path.join(into, "#{name}.log"), Enum.join(said, "\n"))
      Mix.shell().info("logged  #{length(said)} message(s), in #{name}.log")
      for message <- said, do: Mix.shell().info("        #{message}")
    end

    case Browser.transport(browser) do
      nil -> Mix.shell().info("socket  none opened")
      transport -> Mix.shell().info("socket  #{transport}")
    end
  end

  # Named for what was looked at and how wide, so two widths of one surface do not
  # overwrite each other and a directory of them reads as a record.
  defp name(path, width) do
    slug =
      path
      |> String.split(~r{[/?&=]}, trim: true)
      |> Enum.map_join("-", &String.slice(&1, 0, 24))

    if slug == "", do: "root-#{width}", else: "#{slug}-#{width}"
  end
end
