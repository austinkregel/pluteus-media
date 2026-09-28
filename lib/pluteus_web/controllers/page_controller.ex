defmodule PluteusWeb.PageController do
  use PluteusWeb, :controller

  alias Pluteus.Design.Tokens
  alias PluteusWeb.Notices

  @doc """
  The design language, rendered.

  Until spec-10 §9's surfaces exist there is nothing else for this address to be,
  and Annex A's own review criterion (A.9.2) is that every rendering exists rather
  than that the populated one looks right — which needs somewhere the renderings can
  be seen side by side and every context switched over them.

  The roles are read from the token file rather than listed here, so a role added to
  the language appears without this page being edited. A swatch therefore names its
  variable rather than a utility class: A.9.5 requires a class name be a complete
  literal string, and a name assembled at run time produces no rule at all.
  """
  def home(conn, _params) do
    render(conn, :home, roles: roles(), ramp: ramp(), scale: scale())
  end

  @doc """
  The third-party notices.

  A.8.1 puts half of the glyph set's licence obligation beside the vendored files and
  the other half here, so this is a surface the licence requires rather than a courtesy.
  """
  def notices(conn, _params) do
    render(conn, :notices, page_title: "Third-party notices", notices: Notices.all())
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
    name = String.replace_prefix(path, "sys.color.", "")
    {name, "--sys-color-" <> String.replace(name, ".", "-")}
  end

  defp ramp do
    for step <- ~w(01 02 03 04 05 06 07 08 09 10 11 12 ring) do
      {step, "--color-grey-#{step}"}
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

      {name, "--sys-type-" <> String.replace(name, ".", "-"), "#{value["value"]}#{value["unit"]}"}
    end)
  end
end
