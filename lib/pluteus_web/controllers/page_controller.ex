defmodule PluteusWeb.PageController do
  use PluteusWeb, :controller

  alias Pluteus.Design.Build
  alias Pluteus.Design.Glyphs
  alias Pluteus.Design.Tokens
  alias PluteusWeb.Notices

  @doc """
  The design language, rendered.

  Annex A's own review criterion (A.9.2) is that every rendering exists rather than
  that the populated one looks right, which needs somewhere the renderings can be seen
  side by side and every context switched over them. That is what this is, and it is why
  it has an address of its own rather than the catalogue's.

  The roles are read from the token file rather than listed here, so a role added to
  the language appears without this page being edited. A swatch therefore names its
  variable rather than a utility class: A.9.5 requires a class name be a complete
  literal string, and a name assembled at run time produces no rule at all.
  """
  def home(conn, _params) do
    render(conn, :home,
      roles: roles(),
      ramp: ramp(),
      scale: scale(),
      glyphs: glyphs(),
      markers: markers()
    )
  end

  # A.9.5 admits no name assembled in a template, so each marker arrives with the whole
  # one it is drawn under.
  defp markers do
    for {state, contour, field, mark} <- Glyphs.markers() do
      {state, "state-#{state}-micro", contour, field, mark}
    end
  end

  @doc """
  The third-party notices.

  A.8.1 puts half of the glyph set's licence obligation beside the vendored files and
  the other half here, so this is a surface the licence requires rather than a courtesy.
  """
  def notices(conn, _params) do
    render(conn, :notices, page_title: "Third-party notices", notices: Notices.all())
  end

  # Each drawn glyph beside the base-set glyph A.8.6 says it is hardest to tell from, at
  # every grid. The pairing is the point: A.8.5's own standard is whether a reduction
  # preserves the meaning, and that is a judgement nothing here can make — so the two are
  # rendered side by side at the size where the question is live.
  defp glyphs do
    [
      {"scan", "hero-document-text",
       "Both are a sheet of paper. The scanner bar crossing beyond the sheet's edges is " <>
         "the whole separator, and it has to still separate them at 16."},
      {"audiobook", "hero-book-open",
       "Both are an open book. The arc rising clear of the book's outer edge is the " <>
         "separator, which is why it is drawn outside the silhouette rather than over it."},
      {"comic-issue", nil,
       "A page of unequal panels. The division is the shape rather than a line, so it " <>
         "cannot thin away as the grid shrinks."},
      {"music-recording", nil,
       "A disk. The groove goes at 16 rather than shrinking; the centre hole is what " <>
         "says disk and it is kept at every grid."},
      {"video-game", nil,
       "A gamepad. The directional cross is one shape, because two crossing holes wind " <>
         "to minus one where they meet and the centre fills back in."}
    ]
  end

  defp roles do
    Tokens.all()
    |> Map.keys()
    |> Enum.filter(&String.starts_with?(&1, "sys.color."))
    |> Enum.sort()
    |> Enum.group_by(&group/1, &leaf/1)
  end

  # The role's group, which is every segment between `sys.color.` and the last one.
  defp group(path) do
    path
    |> String.replace_prefix("sys.color.", "")
    |> String.split(".")
    |> Enum.drop(-1)
    |> Enum.join(".")
  end

  defp leaf(path) do
    {String.replace_prefix(path, "sys.color.", ""), Build.variable(path)}
  end

  defp ramp do
    for step <- ~w(01 02 03 04 05 06 07 08 09 10 11 12 ring) do
      {step, Build.variable("base.grey.#{step}")}
    end
  end

  defp scale do
    Tokens.all()
    |> Map.keys()
    |> Enum.filter(&String.starts_with?(&1, "sys.type."))
    |> Enum.reject(&String.starts_with?(&1, "sys.type.family"))
    |> Enum.sort_by(&Tokens.resolve!(&1)["value"], :desc)
    |> Enum.map(fn path ->
      name = String.replace_prefix(path, "sys.type.", "")
      value = Tokens.resolve!(path)

      {name, Build.variable(path), "#{value["value"]}#{value["unit"]}"}
    end)
  end
end
