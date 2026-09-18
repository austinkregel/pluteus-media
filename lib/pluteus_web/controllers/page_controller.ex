defmodule PluteusWeb.PageController do
  use PluteusWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
