defmodule MirrorWeb.MapLoadPathTest do
  @moduledoc """
  The Load box's default path must be a real path on this OS. It used to
  swap `/` for `\\`, which on macOS/Linux became a relative filename that
  never loads.
  """
  use MirrorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    previous = System.get_env("MIRROR_MOM_PATH")
    dir = Path.join(System.tmp_dir!(), "mirror game dir")
    System.put_env("MIRROR_MOM_PATH", dir)

    on_exit(fn ->
      if previous,
        do: System.put_env("MIRROR_MOM_PATH", previous),
        else: System.delete_env("MIRROR_MOM_PATH")
    end)

    conn =
      init_test_session(conn, %{"mirror_session_id" => "load-path-#{System.unique_integer()}"})

    %{conn: conn, dir: dir}
  end

  test "defaults to SAVE1.GAM in MIRROR_MOM_PATH, as a native path", %{conn: conn, dir: dir} do
    {:ok, view, _html} = live(conn, "/arcanus")

    [value] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#load-form input[type=text]")
      |> LazyHTML.attribute("value")

    assert value == Path.join(dir, "SAVE1.GAM")
    refute value =~ "\\"
  end
end
