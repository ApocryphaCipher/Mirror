defmodule MirrorWeb.PageController do
  use MirrorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
