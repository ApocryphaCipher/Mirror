defmodule MirrorWeb.MapLiveEditTest do
  @moduledoc """
  View vs edit mode on the map pages (STORY-016, 022, 023, 026, 027).

  Needs a real save: run `bash scripts/test_game.sh`. Works on a temp copy of
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

  # Open the map, load the save, enter edit mode with the given tool.
  defp editing(conn, save, tool \\ "cycle") do
    {:ok, view, _} = live(conn, ~p"/arcanus")
    view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})
    render_click(view, "toggle_edit", %{})
    render_click(view, "set_tool", %{"tool" => tool})
    view
  end

  defp reopen_in_edit(conn) do
    {:ok, view, _} = live(conn, ~p"/arcanus")
    render_click(view, "toggle_edit", %{})
    view
  end

  defp changed(view), do: view |> element("#changed-tiles") |> render() |> text_of()

  defp text_of(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.text() |> String.trim()

  defp pointer(view, action, x, y, opts \\ []) do
    render_hook(view, "map_pointer", %{
      "action" => action,
      "x" => x,
      "y" => y,
      "button" => Keyword.get(opts, :button, 0),
      "mods" => %{"shift" => Keyword.get(opts, :shift, false)}
    })
  end

  defp click(view, x, y, opts \\ []) do
    pointer(view, "start", x, y, opts)
    pointer(view, "end", x, y, opts)
  end

  # Current tile number at (x, y), read from the hover readout.
  defp tile_at(view, x, y) do
    pointer(view, "hover", x, y)
    [_, n] = Regex.run(~r/tile (\d+)/, view |> element("#hover-readout") |> render() |> text_of())
    String.to_integer(n)
  end

  defp paint(view, x, y, tile) do
    render_click(view, "set_tool", %{"tool" => "paint"})
    view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "#{tile}"}})
    click(view, x, y)
  end

  describe "view mode" do
    test "ignores paint and wheel input", %{conn: conn, save: save} do
      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      click(view, 1, 1)
      pointer(view, "drag", 2, 1)
      render_hook(view, "map_pointer", %{"action" => "wheel", "delta" => -100, "mods" => %{}})

      refute has_element?(view, "#unsaved-notice")
      assert changed(reopen_in_edit(conn)) =~ "0 tiles changed"
    end

    test "a reload never lands in edit mode, but keeps the draft (STORY-026)",
         %{conn: conn, save: save} do
      view = editing(conn, save)
      click(view, 1, 1)

      {:ok, reloaded, _} = live(conn, ~p"/arcanus?edit=terrain")
      refute has_element?(reloaded, "#edit-toolbar")
      assert reloaded |> element("#unsaved-notice") |> render() =~ "1 unsaved change"
    end

    test "the unsaved notice can discard, with an in-page confirm", %{conn: conn, save: save} do
      view = editing(conn, save)
      click(view, 1, 1)
      render_click(view, "toggle_edit", %{})

      render_click(view, "arm_discard", %{})
      assert has_element?(view, "#confirm-discard-button")
      render_click(view, "discard_edits", %{})
      refute has_element?(view, "#unsaved-notice")
    end
  end

  describe "Cycle tool (STORY-027)" do
    test "click steps the tile +1; right-click and shift-click step back",
         %{conn: conn, save: save} do
      view = editing(conn, save)
      start = tile_at(view, 5, 5)

      click(view, 5, 5)
      assert tile_at(view, 5, 5) == Integer.mod(start + 1, 762)
      click(view, 5, 5)
      assert tile_at(view, 5, 5) == Integer.mod(start + 2, 762)

      click(view, 5, 5, button: 2)
      assert tile_at(view, 5, 5) == Integer.mod(start + 1, 762)
      click(view, 5, 5, shift: true)
      assert tile_at(view, 5, 5) == start
    end

    test "wraps at both ends", %{conn: conn, save: save} do
      view = editing(conn, save)
      paint(view, 6, 6, 761)
      render_click(view, "set_tool", %{"tool" => "cycle"})

      click(view, 6, 6)
      assert tile_at(view, 6, 6) == 0
      click(view, 6, 6, button: 2)
      assert tile_at(view, 6, 6) == 761
    end

    test "each click is one undo step, pushed live", %{conn: conn, save: save} do
      view = editing(conn, save)
      start = tile_at(view, 7, 7)

      click(view, 7, 7)
      assert_push_event(view, "engine_delta", %{changes: [%{x: 7, y: 7}]})
      click(view, 7, 7)

      render_click(view, "undo", %{})
      assert tile_at(view, 7, 7) == Integer.mod(start + 1, 762)
      render_click(view, "undo", %{})
      assert tile_at(view, 7, 7) == start
    end
  end

  describe "Paint tool" do
    test "paints, undoes and redoes", %{conn: conn, save: save} do
      view = editing(conn, save, "paint")
      view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "5"}})

      click(view, 1, 1)
      assert changed(view) =~ "1 tile changed"

      render_click(view, "undo", %{})
      assert changed(view) =~ "0 tiles changed"

      render_click(view, "redo", %{})
      assert changed(view) =~ "1 tile changed"
    end

    test "painting, undo and redo push the tile to the canvas (STORY-023)",
         %{conn: conn, save: save} do
      view = editing(conn, save, "paint")
      view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "5"}})

      pointer(view, "start", 1, 1)

      assert_push_event(view, "engine_delta", %{
        layer: "terrain",
        changes: [%{x: 1, y: 1, new: 5}]
      })

      pointer(view, "end", 1, 1)

      render_click(view, "undo", %{})

      assert_push_event(view, "engine_delta", %{
        layer: "terrain",
        changes: [%{x: 1, y: 1, prev: 5}]
      })

      render_click(view, "redo", %{})

      assert_push_event(view, "engine_delta", %{
        layer: "terrain",
        changes: [%{x: 1, y: 1, new: 5}]
      })
    end

    test "a stroke is undoable even if it never finishes", %{conn: conn, save: save} do
      view = editing(conn, save, "paint")
      view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "5"}})

      pointer(view, "start", 3, 3)
      pointer(view, "drag", 4, 3)
      # No "end": the LiveView goes away mid-stroke (reload, crash, navigation).

      again = reopen_in_edit(conn)
      assert changed(again) =~ "2 tiles changed"
      render_click(again, "undo", %{})
      assert changed(again) =~ "0 tiles changed"
    end

    test "brush is clamped to real tile numbers", %{conn: conn, save: save} do
      view = editing(conn, save, "paint")
      html = view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "99999"}})
      assert html =~ ~s(value="761")
    end
  end

  test "save as refuses the loaded file, writes a new one, and discard restores",
       %{conn: conn, dir: dir, save: save} do
    view = editing(conn, save)
    original = File.read!(save)
    click(view, 1, 1)

    html = view |> element("#save-form") |> render_submit(%{"save" => %{"path" => save}})
    assert html =~ "won&#39;t overwrite"
    assert File.read!(save) == original

    target = Path.join(dir, "SAVE2.GAM")
    view |> element("#save-form") |> render_submit(%{"save" => %{"path" => target}})
    assert File.exists?(target)
    assert File.read!(target) != original
    assert changed(view) =~ "0 tiles changed"

    click(view, 2, 2)
    assert changed(view) =~ "1 tile changed"
    render_click(view, "arm_discard", %{})
    render_click(view, "discard_edits", %{})
    assert changed(view) =~ "0 tiles changed"
  end

  describe "cities overlay (STORY-010)" do
    test "loading a save pushes this plane's cities with owner banners", %{conn: conn, save: save} do
      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      assert_push_event(view, "overlay_data", %{layer: "cities", items: items})
      assert length(items) == 16
      assert %{x: 38, y: 21, size: 1, banner: :yellow, name: "Deventor"} in items

      assert_push_event(view, "overlay_sprites", %{cities: %{unwalled: %{width: 32, height: 30}}})
    end
  end
end
