defmodule MirrorWeb.MapLiveEditTest do
  @moduledoc """
  View vs edit mode on the map pages (STORY-016, STORY-022).

  Needs a real save: run with the same env as `scripts/dev_server.sh`
  (MIRROR_MOM_PATH + the MIRROR_*_OFFSET vars). Works on a temp copy of
  SAVE1.GAM, so the real file is never touched.
  """
  use MirrorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @mom_path System.get_env("MIRROR_MOM_PATH")
  @save_source @mom_path && Path.join(@mom_path, "SAVE1.GAM")
  @has_save @save_source && File.exists?(@save_source) &&
              System.get_env("MIRROR_TERRAIN_OFFSET") != nil

  @moduletag skip: !@has_save && "needs MIRROR_MOM_PATH/SAVE1.GAM and MIRROR_*_OFFSET env"

  setup %{conn: conn} do
    dir = Path.join(System.tmp_dir!(), "mirror-edit-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    save = Path.join(dir, "SAVE1.GAM")
    File.cp!(@save_source, save)
    on_exit(fn -> File.rm_rf!(dir) end)

    conn =
      init_test_session(conn, %{"mirror_session_id" => "edit-test-#{System.unique_integer()}"})

    %{conn: conn, dir: dir, save: save}
  end

  defp load(view, save) do
    view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})
  end

  defp changed(view), do: view |> element("#changed-tiles") |> render() |> text_of()

  defp text_of(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.text() |> String.trim()

  defp pointer(view, action, x, y, button \\ 0) do
    render_hook(view, "map_pointer", %{
      "action" => action,
      "x" => x,
      "y" => y,
      "button" => button,
      "mods" => %{}
    })
  end

  test "view mode ignores paint and wheel input", %{conn: conn, save: save} do
    {:ok, view, _} = live(conn, ~p"/arcanus")
    load(view, save)

    pointer(view, "start", 1, 1)
    pointer(view, "drag", 2, 1)
    pointer(view, "end", 2, 1)
    render_hook(view, "map_pointer", %{"action" => "wheel", "delta" => -100, "mods" => %{}})

    {:ok, edit, _} = live(conn, ~p"/arcanus?edit=terrain")
    assert changed(edit) =~ "0 tiles changed"
  end

  test "edit mode paints, undoes and redoes", %{conn: conn, save: save} do
    {:ok, view, _} = live(conn, ~p"/arcanus?edit=terrain")
    load(view, save)
    view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "5"}})

    pointer(view, "start", 1, 1)
    pointer(view, "end", 1, 1)
    assert changed(view) =~ "1 tile changed"

    render_click(view, "undo", %{})
    assert changed(view) =~ "0 tiles changed"

    render_click(view, "redo", %{})
    assert changed(view) =~ "1 tile changed"
  end

  test "painting, undo and redo push the tile to the canvas (STORY-023)",
       %{conn: conn, save: save} do
    {:ok, view, _} = live(conn, ~p"/arcanus?edit=terrain")
    load(view, save)
    view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "5"}})

    pointer(view, "start", 1, 1)
    assert_push_event(view, "engine_delta", %{layer: "terrain", changes: [%{x: 1, y: 1, new: 5}]})
    pointer(view, "end", 1, 1)

    render_click(view, "undo", %{})

    assert_push_event(view, "engine_delta", %{layer: "terrain", changes: [%{x: 1, y: 1, prev: 5}]})

    render_click(view, "redo", %{})
    assert_push_event(view, "engine_delta", %{layer: "terrain", changes: [%{x: 1, y: 1, new: 5}]})
  end

  test "a stroke is undoable even if it never finishes", %{conn: conn, save: save} do
    {:ok, view, _} = live(conn, ~p"/arcanus?edit=terrain")
    load(view, save)
    view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "5"}})

    pointer(view, "start", 3, 3)
    pointer(view, "drag", 4, 3)
    # No "end": the LiveView goes away mid-stroke (reload, crash, navigation).

    {:ok, again, _} = live(conn, ~p"/arcanus?edit=terrain")
    assert changed(again) =~ "2 tiles changed"
    render_click(again, "undo", %{})
    assert changed(again) =~ "0 tiles changed"
  end

  test "brush is clamped to real tile numbers", %{conn: conn, save: save} do
    {:ok, view, _} = live(conn, ~p"/arcanus?edit=terrain")
    load(view, save)
    html = view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "99999"}})
    assert html =~ ~s(value="761")
  end

  test "save as refuses the loaded file, writes a new one, and discard restores",
       %{conn: conn, dir: dir, save: save} do
    {:ok, view, _} = live(conn, ~p"/arcanus?edit=terrain")
    load(view, save)
    original = File.read!(save)

    view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "5"}})
    pointer(view, "start", 1, 1)
    pointer(view, "end", 1, 1)

    html = view |> element("#save-form") |> render_submit(%{"save" => %{"path" => save}})
    assert html =~ "won&#39;t overwrite"
    assert File.read!(save) == original

    target = Path.join(dir, "SAVE2.GAM")
    view |> element("#save-form") |> render_submit(%{"save" => %{"path" => target}})
    assert File.exists?(target)
    assert File.read!(target) != original
    assert changed(view) =~ "0 tiles changed"

    pointer(view, "start", 2, 2)
    pointer(view, "end", 2, 2)
    assert changed(view) =~ "1 tile changed"
    render_click(view, "discard_edits", %{})
    assert changed(view) =~ "0 tiles changed"
  end
end
