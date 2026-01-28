defmodule MirrorWeb.ErrorJSONTest do
  use MirrorWeb.ConnCase, async: true

  test "renders 404" do
    assert MirrorWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert MirrorWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
