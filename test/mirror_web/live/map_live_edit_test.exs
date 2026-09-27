defmodule MirrorWeb.MapLiveEditTest do
  @moduledoc """
  View vs edit mode on the map pages (STORY-016, 022, 023, 026, 027).

  Uses a synthetic save fixture so editing, undo, discard, Save as and Surveyor
  tests run unconditionally in CI without needing game files (STORY-041).
  A handful of real-save tests run only when MIRROR_MOM_PATH and save offsets are present.
  """
  use MirrorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @mom_path System.get_env("MIRROR_MOM_PATH")
  @real_save_source @mom_path && Path.join(@mom_path, "SAVE1.GAM")
  @has_real_save @real_save_source && File.exists?(@real_save_source) &&
                   System.get_env("MIRROR_TERRAIN_OFFSET") != nil
  @has_real_save_and_sprites @has_real_save &&
                               File.exists?(Path.join(@mom_path, "MAPBACK.LBX"))

  setup %{conn: conn} do
    dir = Path.join(System.tmp_dir!(), "mirror-edit-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    save = Path.join(dir, "SAVE1.GAM")
    File.write!(save, synthetic_save_bytes())
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

    test "discard terminates superseded engine session (STORY-039)", %{conn: conn, save: save} do
      session_id = "engine-term-test-#{System.unique_integer([:positive])}"
      conn = init_test_session(conn, %{"mirror_session_id" => session_id})
      view = editing(conn, save, "cycle")

      state = Mirror.SessionStore.get(session_id)
      old_engine_id = state.engine_session_id
      assert old_engine_id != nil
      old_pid = Mirror.Engine.Session.whereis(old_engine_id)
      assert Process.alive?(old_pid)

      click(view, 1, 1)
      render_click(view, "arm_discard", %{})
      render_click(view, "discard_edits", %{})

      refute Process.alive?(old_pid)

      new_engine_id = Mirror.SessionStore.get(session_id).engine_session_id
      assert new_engine_id != nil
      assert new_engine_id != old_engine_id
      new_pid = Mirror.Engine.Session.whereis(new_engine_id)
      assert Process.alive?(new_pid)
    end
  end

  describe "multi-tab session synchronization (STORY-039)" do
    test "two tabs on one session sync edits without overwriting", %{conn: conn, save: save} do
      session_id = "two-tab-test-#{System.unique_integer([:positive])}"
      conn1 = init_test_session(conn, %{"mirror_session_id" => session_id})
      conn2 = init_test_session(conn, %{"mirror_session_id" => session_id})

      {:ok, tab1, _} = live(conn1, ~p"/arcanus")
      tab1 |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      {:ok, tab2, _} = live(conn2, ~p"/arcanus")

      # Tab 1 enters edit mode and paints a tile
      render_click(tab1, "toggle_edit", %{})
      render_click(tab1, "set_tool", %{"tool" => "cycle"})
      click(tab1, 1, 1)

      assert changed(tab1) =~ "1 tile changed"

      # Tab 2 receives the synchronized state
      render_click(tab2, "toggle_edit", %{})
      assert changed(tab2) =~ "1 tile changed"

      # Tab 2 changes tool (writing to SessionStore)
      render_click(tab2, "set_tool", %{"tool" => "paint"})

      # Verify Tab 1's edit was preserved in SessionStore and in both tabs
      assert changed(tab2) =~ "1 tile changed"
      assert changed(tab1) =~ "1 tile changed"
    end

    test "competing concurrent edits from two tabs with same starting state both survive (STORY-039)",
         %{conn: conn, save: save} do
      session_id = "competing-tab-test-#{System.unique_integer([:positive])}"
      conn1 = init_test_session(conn, %{"mirror_session_id" => session_id})
      conn2 = init_test_session(conn, %{"mirror_session_id" => session_id})

      {:ok, tab1, _} = live(conn1, ~p"/arcanus")
      tab1 |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      {:ok, tab2, _} = live(conn2, ~p"/arcanus")

      # Both tabs enter edit mode with cycle tool
      render_click(tab1, "toggle_edit", %{})
      render_click(tab1, "set_tool", %{"tool" => "cycle"})
      render_click(tab2, "toggle_edit", %{})
      render_click(tab2, "set_tool", %{"tool" => "cycle"})

      # Both tabs start from the same baseline state (0 edits)
      assert changed(tab1) =~ "0 tiles changed"
      assert changed(tab2) =~ "0 tiles changed"

      # Both tabs execute edits concurrently without waiting on each other's broadcast
      t1 = Task.async(fn -> click(tab1, 1, 1) end)
      t2 = Task.async(fn -> click(tab2, 2, 2) end)
      Task.await(t1)
      Task.await(t2)

      # Both edits survive in the synchronized SessionStore and in both tabs
      state = Mirror.SessionStore.get(session_id)
      plane = state.planes.arcanus.terrain

      assert Mirror.Map.get_tile_u16_le(plane, 1, 1) !=
               Mirror.Map.get_tile_u16_le(state.original_planes.arcanus.terrain, 1, 1)

      assert Mirror.Map.get_tile_u16_le(plane, 2, 2) !=
               Mirror.Map.get_tile_u16_le(state.original_planes.arcanus.terrain, 2, 2)

      assert changed(tab1) =~ "2 tiles changed"
      assert changed(tab2) =~ "2 tiles changed"
    end

    test "saving from a tab with stale socket state preserves concurrent edits from another tab (STORY-043)",
         %{conn: conn, dir: dir, save: save} do
      session_id = "stale-save-test-#{System.unique_integer([:positive])}"
      conn1 = init_test_session(conn, %{"mirror_session_id" => session_id})

      {:ok, tab1, _} = live(conn1, ~p"/arcanus")
      tab1 |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})
      render_click(tab1, "toggle_edit", %{})
      render_click(tab1, "set_tool", %{"tool" => "cycle"})
      click(tab1, 1, 1)
      assert changed(tab1) =~ "1 tile changed"

      # Simulate Tab B committing an edit directly into SessionStore (e.g. before Tab 1's broadcast arrives)
      current_store = Mirror.SessionStore.get(session_id)
      tab1_edited_val = Mirror.Map.get_tile_u16_le(current_store.planes.arcanus.terrain, 1, 1)
      baseline_at_2_2 = Mirror.Map.get_tile_u16_le(current_store.planes.arcanus.terrain, 2, 2)
      tab2_edited_val = Integer.mod(baseline_at_2_2 + 10, 762)

      {tab2_state, _change, _updates} =
        Mirror.Editor.apply_tile(current_store, :arcanus, :terrain, 2, 2, tab2_edited_val)

      :ets.insert(:mirror_sessions, {session_id, tab2_state})

      # Tab 1 now submits save to SAVE2.GAM with its stale socket assigns
      target_save = Path.join(dir, "SAVE2.GAM")
      tab1 |> element("#save-form") |> render_submit(%{"save" => %{"path" => target_save}})

      # Both Tab 1's edit at (1, 1) and Tab 2's edit at (2, 2) must survive in SessionStore
      store_after = Mirror.SessionStore.get(session_id)

      assert Mirror.Map.get_tile_u16_le(store_after.planes.arcanus.terrain, 1, 1) ==
               tab1_edited_val

      assert Mirror.Map.get_tile_u16_le(store_after.planes.arcanus.terrain, 2, 2) ==
               tab2_edited_val

      # Both edits must survive in the file written to disk
      assert File.exists?(target_save)
      {:ok, loaded_save} = Mirror.SaveFile.load(target_save)

      assert Mirror.Map.get_tile_u16_le(loaded_save.planes.arcanus.terrain, 1, 1) ==
               tab1_edited_val

      assert Mirror.Map.get_tile_u16_le(loaded_save.planes.arcanus.terrain, 2, 2) ==
               tab2_edited_val
    end

    test "stroke resolves brush value from current session store even if tab socket selection is stale (STORY-043)",
         %{conn: conn, save: save} do
      session_id = "stale-brush-test-#{System.unique_integer([:positive])}"
      conn1 = init_test_session(conn, %{"mirror_session_id" => session_id})

      {:ok, tab1, _} = live(conn1, ~p"/arcanus")
      tab1 |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})
      render_click(tab1, "toggle_edit", %{})
      render_click(tab1, "set_tool", %{"tool" => "paint"})

      # Simulate Tab B updating the active brush selection in SessionStore
      # without Tab 1 having processed the broadcast
      current_store = Mirror.SessionStore.get(session_id)
      updated_selection = Map.put(current_store.selection, :terrain, 42)
      :ets.insert(:mirror_sessions, {session_id, %{current_store | selection: updated_selection}})

      # Tab 1 starts painting at (3, 3)
      pointer(tab1, "start", 3, 3)
      pointer(tab1, "end", 3, 3)

      # The painted tile must be 42 from the authoritative current session
      store_after = Mirror.SessionStore.get(session_id)
      assert Mirror.Map.get_tile_u16_le(store_after.planes.arcanus.terrain, 3, 3) == 42
    end

    test "concurrent stroke continuation preserves interleaved stroke from another tab (STORY-043)",
         %{conn: conn, save: save} do
      session_id = "concurrent-drag-stroke-test-#{System.unique_integer([:positive])}"
      conn1 = init_test_session(conn, %{"mirror_session_id" => session_id})
      conn2 = init_test_session(conn, %{"mirror_session_id" => session_id})

      {:ok, tab1, _} = live(conn1, ~p"/arcanus")
      tab1 |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})
      render_click(tab1, "toggle_edit", %{})
      render_click(tab1, "set_tool", %{"tool" => "paint"})

      {:ok, tab2, _} = live(conn2, ~p"/arcanus")
      render_click(tab2, "toggle_edit", %{})
      render_click(tab2, "set_tool", %{"tool" => "cycle"})

      # Baseline value at (5, 5)
      start_store = Mirror.SessionStore.get(session_id)
      baseline_at_5_5 = Mirror.Map.get_tile_u16_le(start_store.planes.arcanus.terrain, 5, 5)

      # Tab 1 starts a drag stroke (pointer start at 1, 1 then drag to 1, 2)
      pointer(tab1, "start", 1, 1)
      pointer(tab1, "drag", 1, 2)

      # Tab 2 commits a separate single-tile cycle stroke at (5, 5) in between Tab 1's moves
      click(tab2, 5, 5)

      # Tab 1 continues drag to (1, 3) and ends stroke
      pointer(tab1, "drag", 1, 3)
      pointer(tab1, "end", 1, 3)

      # Both Tab 1's drag tiles and Tab 2's cycle tile are present
      store_after = Mirror.SessionStore.get(session_id)

      assert Mirror.Map.get_tile_u16_le(store_after.planes.arcanus.terrain, 5, 5) ==
               Integer.mod(baseline_at_5_5 + 1, 762)

      # Undoing once in Tab 1 pops Tab 2's stroke (the head of history)
      render_click(tab1, "undo", %{})

      store_after_undo = Mirror.SessionStore.get(session_id)
      # Tab 2's tile was undone back to baseline
      assert Mirror.Map.get_tile_u16_le(store_after_undo.planes.arcanus.terrain, 5, 5) ==
               baseline_at_5_5

      # Tab 1's drag tiles (1, 1), (1, 2), (1, 3) are still intact
      brush_val = Map.get(start_store.selection, :terrain, 0)

      assert Mirror.Map.get_tile_u16_le(store_after_undo.planes.arcanus.terrain, 1, 1) ==
               brush_val

      assert Mirror.Map.get_tile_u16_le(store_after_undo.planes.arcanus.terrain, 1, 2) ==
               brush_val

      assert Mirror.Map.get_tile_u16_le(store_after_undo.planes.arcanus.terrain, 1, 3) ==
               brush_val
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

    test "undo and redo keep research statistics in sync (STORY-039)", %{conn: conn, save: save} do
      {:ok, dataset_id} = Mirror.Stats.dataset_id_from_path(save)
      view = editing(conn, save, "cycle")

      before_hist = Mirror.Stats.histogram(dataset_id, :computed_adj_mask, :global)
      before_rays = ray_observations(dataset_id)

      click(view, 5, 5)
      after_click_hist = Mirror.Stats.histogram(dataset_id, :computed_adj_mask, :global)
      after_click_rays = ray_observations(dataset_id)
      assert after_click_hist != before_hist
      assert after_click_rays != before_rays

      render_click(view, "undo", %{})
      after_undo_hist = Mirror.Stats.histogram(dataset_id, :computed_adj_mask, :global)
      after_undo_rays = ray_observations(dataset_id)
      assert after_undo_hist == before_hist
      assert after_undo_rays == before_rays

      render_click(view, "redo", %{})
      after_redo_hist = Mirror.Stats.histogram(dataset_id, :computed_adj_mask, :global)
      after_redo_rays = ray_observations(dataset_id)
      assert after_redo_hist == after_click_hist
      assert after_redo_rays == after_click_rays
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

    test "terrain edits push recomputed adjacency masks to client (STORY-039)",
         %{conn: conn, save: save} do
      view = editing(conn, save, "paint")
      view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "5"}})

      pointer(view, "start", 1, 1)

      assert_push_event(view, "engine_delta", %{
        layer: "computed_adj_mask",
        changes: adj_changes
      })

      assert Enum.any?(adj_changes, &match?(%{x: 1, y: 1}, &1))
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

    test "a drag starting on a matching tile paints subsequent tiles (STORY-039)",
         %{conn: conn, save: save} do
      view = editing(conn, save, "paint")
      start_1_1 = tile_at(view, 1, 1)

      view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "#{start_1_1}"}})

      pointer(view, "start", 1, 1)
      pointer(view, "drag", 2, 1)
      pointer(view, "end", 2, 1)

      assert tile_at(view, 2, 1) == start_1_1
      assert changed(view) =~ "1 tile changed"

      render_click(view, "undo", %{})
      assert changed(view) =~ "0 tiles changed"
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

  test "after Save as, discard reloads engine from last-saved planes (STORY-039)",
       %{conn: conn, dir: dir, save: save} do
    view = editing(conn, save)
    start_1_1 = tile_at(view, 1, 1)
    click(view, 1, 1)
    saved_tile_1_1 = tile_at(view, 1, 1)
    assert saved_tile_1_1 != start_1_1

    target = Path.join(dir, "SAVE2.GAM")
    view |> element("#save-form") |> render_submit(%{"save" => %{"path" => target}})

    # Paint another tile after Save as
    click(view, 2, 2)
    assert changed(view) =~ "1 tile changed"

    # Discard edits: should restore to SAVE2.GAM planes, and hover inspection must match
    render_click(view, "arm_discard", %{})
    render_click(view, "discard_edits", %{})
    assert changed(view) =~ "0 tiles changed"

    assert tile_at(view, 1, 1) == saved_tile_1_1
  end

  describe "cities overlay (STORY-010)" do
    test "loading a save pushes this plane's cities with owner banners", %{conn: conn, save: save} do
      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      assert_push_event(view, "overlay_data", %{layer: "cities", items: items})
      assert length(items) == 16
      assert %{x: 38, y: 21, size: 1, banner: :yellow, name: "Deventor", walled: false} in items
    end

    test "the hover readout names the city under the pointer (STORY-032)", %{
      conn: conn,
      save: save
    } do
      # City Walls for record 0 (Deventor): byte +66 of the block at 0x8aac.
      File.write!(save, put_byte(File.read!(save), 0x8AAC + 66, 1))

      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      assert_push_event(view, "overlay_data", %{layer: "cities", items: items})
      assert %{name: "Deventor", walled: true} = Enum.find(items, &(&1.name == "Deventor"))

      pointer(view, "hover", 38, 21)

      assert view |> element("#hover-city") |> render() |> text_of() =~
               ~r/Deventor\s+\(Hamlet, walled\)/

      pointer(view, "hover", 0, 0)
      refute has_element?(view, "#hover-city")
    end
  end

  describe "Surveyor (STORY-034)" do
    test "hovering shows the tile, what's on it, and City Resources or why not", %{
      conn: conn,
      save: save
    } do
      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      pointer(view, "hover", 38, 21)
      card = view |> element("#surveyor") |> render() |> text_of()
      assert card =~ ~r/Hills\s*1\/2 food\s*\+3% production\s*Hamlet of\s*Deventor/

      assert card =~
               ~r/City Resources\s*Maximum Pop\s*\d+\s*Prod Bonus\s*\+\d+%\s*Gold Bonus\s*\+\d+%/

      pointer(view, "hover", 39, 20)

      assert view |> element("#surveyor") |> render() |> text_of() =~
               ~r/Mountain\s*\+5% production\s*Gold Ore\s*\+3 gold\s*Cities cannot be built less than 3 squares/

      pointer(view, "hover", 0, 0)
      assert view |> element("#surveyor") |> render() |> text_of() =~ ~r/Surveyor\s*Unexplored/
    end

    test "is a view-mode tool: edit mode hides it", %{conn: conn, save: save} do
      view = editing(conn, save)
      pointer(view, "hover", 38, 21)
      refute has_element?(view, "#surveyor")
    end
  end

  describe "settleable tiles and fog layers (STORY-035, STORY-036)" do
    test "both are pushed with the map, off by default, and follow edits", %{
      conn: conn,
      save: save
    } do
      {:ok, view, html} = live(conn, ~p"/arcanus")
      refute html =~ ~r/value="fog"[^>]*checked/
      refute html =~ ~r/value="settleable"[^>]*checked/
      assert html =~ ~r/value="cities"[^>]*checked/

      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      assert_push_event(view, "overlay_data", %{layer: "settleable", items: settleable})
      refute Enum.any?(settleable, &match?(%{x: 38, y: 21}, &1))
      assert Enum.all?(settleable, &(&1.max_pop in 0..25))

      # SAVE1 is turn one: most of the map is fog; 15 is fully explored.
      assert_push_event(view, "overlay_data", %{layer: "fog", items: fog})
      assert %{explored: 0} = Enum.find(fog, &match?(%{x: 0, y: 0}, &1))
      refute Enum.any?(fog, &match?(%{x: 38, y: 21}, &1))

      render_click(view, "toggle_edit", %{})
      render_click(view, "set_tool", %{"tool" => "cycle"})
      pointer(view, "start", 10, 10)
      assert_push_event(view, "overlay_data", %{layer: "settleable"})
    end

    test "discard refreshes settleable and fog overlays (STORY-039)", %{conn: conn, save: save} do
      view = editing(conn, save, "cycle")
      pointer(view, "start", 10, 10)
      assert_push_event(view, "overlay_data", %{layer: "settleable"})

      render_click(view, "arm_discard", %{})
      render_click(view, "discard_edits", %{})

      assert_push_event(view, "overlay_data", %{layer: "settleable"})
      assert_push_event(view, "overlay_data", %{layer: "fog"})
    end
  end

  describe "real-save integration" do
    @tag skip:
           !@has_real_save_and_sprites &&
             "needs MIRROR_MOM_PATH/(SAVE1.GAM, MAPBACK.LBX) and MIRROR_*_OFFSET env"
    test "loading real SAVE1.GAM pushes Arcanus cities and sprites", %{conn: conn, dir: dir} do
      real_save = Path.join(dir, "REAL_SAVE1.GAM")
      File.cp!(@real_save_source, real_save)

      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => real_save}})

      assert_push_event(view, "overlay_data", %{layer: "cities", items: items})
      assert length(items) == 16
      assert %{x: 38, y: 21, size: 1, banner: :yellow, name: "Deventor", walled: false} in items

      assert_push_event(view, "overlay_sprites", %{cities: %{city: %{width: 32, height: 30}}})
    end

    @tag skip: !@has_real_save && "needs MIRROR_MOM_PATH/SAVE1.GAM and MIRROR_*_OFFSET env"
    test "real SAVE1.GAM overwrite protection and Save as", %{conn: conn, dir: dir} do
      real_save = Path.join(dir, "REAL_SAVE1.GAM")
      File.cp!(@real_save_source, real_save)
      view = editing(conn, real_save)
      original = File.read!(real_save)
      click(view, 1, 1)

      html = view |> element("#save-form") |> render_submit(%{"save" => %{"path" => real_save}})
      assert html =~ "won&#39;t overwrite"
      assert File.read!(real_save) == original

      target = Path.join(dir, "SAVE2.GAM")
      view |> element("#save-form") |> render_submit(%{"save" => %{"path" => target}})
      assert File.exists?(target)
      assert byte_size(File.read!(target)) == byte_size(original)
      assert File.read!(target) != original
    end

    @tag skip: !@has_real_save && "needs MIRROR_MOM_PATH/SAVE1.GAM and MIRROR_*_OFFSET env"
    test "real SAVE1.GAM surveyor matches known readouts at Deventor", %{conn: conn, dir: dir} do
      real_save = Path.join(dir, "REAL_SAVE1.GAM")
      File.cp!(@real_save_source, real_save)

      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => real_save}})

      pointer(view, "hover", 38, 21)
      card = view |> element("#surveyor") |> render() |> text_of()
      assert card =~ ~r/Hills\s*1\/2 food\s*\+3% production\s*Hamlet of\s*Deventor/
    end
  end

  @save_size 123_300
  @forest 0xA3
  @hills 0x113
  @mountain 0x10A
  @ocean 0x00

  defp synthetic_save_bytes do
    raw = :binary.copy(<<0>>, @save_size)

    # 1. Sites region filled with 0xFF so unused records are off-map (x=255)
    nodes_offset = 0x6058
    sites_end = 0x6628 + 102 * 24
    raw = put_bytes(raw, nodes_offset, :binary.copy(<<0xFF>>, sites_end - nodes_offset))

    # Known tower and magic node from SitesTest
    raw = put_bytes(raw, 0x6610, <<48, 28, 0xFF, 0>>)

    raw =
      put_bytes(raw, nodes_offset, <<42, 10, 0, 0, 5>> <> :binary.copy(<<0>>, 40) <> <<0, 2, 0>>)

    # 2. Wizard 0 banner = 4 (Yellow)
    raw = put_bytes(raw, 0x09E8 + 0x16, <<4>>)

    # 3. Cities: 16 cities so length matches real SAVE1.GAM, with Deventor at (38, 21)
    raw = put_bytes(raw, 0x09E0, <<16::little-16>>)

    deventor =
      String.pad_trailing("Deventor", 14, <<0>>) <>
        <<5, 38, 21, 0, 0, 1, 4>> <>
        :binary.copy(<<0>>, 10) <>
        :binary.copy(<<0xFF>>, 36) <>
        :binary.copy(<<0>>, 26) <>
        :binary.copy(<<0>>, 8) <>
        :binary.copy(<<0>>, 13)

    raw = put_bytes(raw, 0x8AAC, deventor)

    raw =
      Enum.reduce(1..15, raw, fn i, acc ->
        record =
          String.pad_trailing("City#{i}", 14, <<0>>) <>
            <<5, 10 + i * 2, 35, 0, 5, 1, 2>> <>
            :binary.copy(<<0>>, 10) <>
            :binary.copy(<<0xFF>>, 36) <>
            :binary.copy(<<0>>, 26) <>
            :binary.copy(<<0>>, 8) <>
            :binary.copy(<<0>>, 13)

        put_bytes(acc, 0x8AAC + i * 114, record)
      end)

    # 4. Terrain: 2400 tiles per plane.
    # Default forest, (1, 1)=10, (2, 1)=20, (38, 21)=hills, (39, 20)=mountain, (4..6, 4..6)=ocean
    arcanus_tiles =
      for y <- 0..39, x <- 0..59, into: <<>> do
        tile =
          cond do
            x == 1 and y == 1 -> 10
            x == 2 and y == 1 -> 20
            x == 38 and y == 21 -> @hills
            x == 39 and y == 20 -> @mountain
            x in 4..6 and y in 4..6 -> @ocean
            true -> @forest
          end

        <<tile::little-16>>
      end

    myrror_tiles = :binary.copy(<<@ocean::little-16>>, 2400)
    raw = put_bytes(raw, 0x002698, arcanus_tiles <> myrror_tiles)

    # 5. Landmass
    raw = put_bytes(raw, 0x004D98, :binary.copy(<<1>>, 4800))

    # 6. Minerals: 4 (Gold Ore) at (39, 20)
    minerals =
      for y <- 0..39, x <- 0..59, into: <<>> do
        val = if x == 39 and y == 20, do: 4, else: 0
        <<val>>
      end

    raw = put_bytes(raw, 0x013554, minerals <> :binary.copy(<<0>>, 2400))

    # 7. Exploration: 0 at (0, 0), 15 elsewhere
    exploration =
      for y <- 0..39, x <- 0..59, into: <<>> do
        val = if x == 0 and y == 0, do: 0, else: 15
        <<val>>
      end

    raw = put_bytes(raw, 0x014814, exploration <> :binary.copy(<<0>>, 2400))

    # 8. Terrain flags
    raw = put_bytes(raw, 0x01CBB8, :binary.copy(<<0>>, 4800))

    raw
  end

  defp put_bytes(raw, at, bytes) do
    size = byte_size(bytes)
    <<head::binary-size(^at), _::binary-size(^size), tail::binary>> = raw
    head <> bytes <> tail
  end

  defp put_byte(raw, at, byte) do
    put_bytes(raw, at, <<byte>>)
  end

  defp ray_observations(dataset_id) do
    Mirror.Stats.export(dataset_id).data
    |> Enum.filter(fn {k, _v} ->
      String.starts_with?(k, "ray:") or String.starts_with?(k, "ray_pair:")
    end)
    |> Map.new()
  end
end
