defmodule Mirror.SaveManagerTest do
  use ExUnit.Case, async: false

  alias Mirror.{Editor, SaveFile, SaveManager}

  describe "path and message helpers" do
    test "normalize_path trims spaces and quotes" do
      assert SaveManager.normalize_path(nil) == ""
      assert SaveManager.normalize_path("  ") == ""
      assert SaveManager.normalize_path("  /path/to/SAVE1.GAM  ") == "/path/to/SAVE1.GAM"
      assert SaveManager.normalize_path("\"/path/to/SAVE1.GAM\"") == "/path/to/SAVE1.GAM"
      assert SaveManager.normalize_path("'/path/to/SAVE1.GAM'") == "/path/to/SAVE1.GAM"
    end

    test "saved_message distinguishes game-loadable names" do
      assert SaveManager.saved_message("/dir/SAVE1.GAM") == "Saved to /dir/SAVE1.GAM."
      assert SaveManager.saved_message("/dir/SAVE9.GAM") == "Saved to /dir/SAVE9.GAM."

      assert SaveManager.saved_message("/dir/CUSTOM.GAM") =~
               "The game only loads SAVE1.GAM to SAVE9.GAM"
    end

    test "error messages" do
      assert SaveManager.load_error_message({:missing_offset, :terrain}, "") =~
               "Missing block offset for terrain"

      assert SaveManager.load_error_message(:enoent, "") =~
               "Provide a save path before loading"

      assert SaveManager.load_error_message(:enoent, "/bad/path") =~
               "Save file not found at /bad/path"

      assert SaveManager.save_error_message(:no_save) == "Load a save before saving."

      assert SaveManager.save_error_message(:would_overwrite_original) =~
               "Save as won't overwrite the file you loaded"
    end
  end

  describe "state normalization" do
    test "normalize_state initializes default editor state" do
      state = SaveManager.normalize_state(nil)
      assert state.save == nil
      assert state.planes == %{}
      assert state.active_layer == :terrain
      assert state.history == %{arcanus: [], myrror: []}
      assert state.redo == %{arcanus: [], myrror: []}
      assert is_map(state.selection)
      assert is_map(state.layer_visibility)
      assert is_map(state.layer_opacity)
    end
  end

  describe "save orchestration" do
    test "save without loaded save returns error" do
      state = SaveManager.normalize_state(nil)
      assert SaveManager.save(state, "/any/path") == {:error, :no_save}
    end

    test "save rejects overwriting the loaded file" do
      dir = Path.join(System.tmp_dir!(), "save-test-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      orig_path = Path.join(dir, "SAVE1.GAM")
      File.write!(orig_path, :binary.copy(<<0>>, 0x20000))
      on_exit(fn -> File.rm_rf!(dir) end)

      raw_planes = %{
        arcanus: %{terrain: :binary.copy(<<0::little-16>>, 2400)},
        myrror: %{terrain: :binary.copy(<<0::little-16>>, 2400)}
      }

      save = %SaveFile{
        path: orig_path,
        planes: raw_planes,
        raw: :binary.copy(<<0>>, 0x20000)
      }

      state = %{
        save: save,
        save_path: orig_path,
        planes: Editor.with_computed_layers(raw_planes),
        original_planes: raw_planes
      }

      assert SaveManager.save(state, orig_path) == {:error, :would_overwrite_original}
    end

    test "save writes a new file and updates original_planes and save_path" do
      dir = Path.join(System.tmp_dir!(), "save-test-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      orig_path = Path.join(dir, "SAVE1.GAM")
      target_path = Path.join(dir, "SAVE2.GAM")
      File.write!(orig_path, :binary.copy(<<0>>, 0x20000))
      on_exit(fn -> File.rm_rf!(dir) end)

      plane_layers = %{
        terrain: :binary.copy(<<0::little-16>>, 2400),
        terrain_flags: :binary.copy(<<0>>, 2400),
        minerals: :binary.copy(<<0>>, 2400),
        exploration: :binary.copy(<<0>>, 2400),
        landmass: :binary.copy(<<0>>, 2400)
      }

      raw_planes = %{arcanus: plane_layers, myrror: plane_layers}

      save = %SaveFile{
        path: orig_path,
        planes: raw_planes,
        raw: :binary.copy(<<0>>, 0x20000)
      }

      state = %{
        save: save,
        save_path: orig_path,
        planes: Editor.with_computed_layers(raw_planes),
        original_planes: raw_planes
      }

      # Modify a tile
      {edited_state, _change, _updates} = Editor.apply_tile(state, :arcanus, :terrain, 0, 0, 99)
      assert Editor.changed_tile_count(edited_state) == 1

      {:ok, saved_state, saved_path} = SaveManager.save(edited_state, target_path)
      assert saved_path == target_path
      assert saved_state.save.path == target_path
      assert saved_state.save_path == target_path
      # After save, changed_tile_count is 0 relative to new saved baseline
      assert Editor.changed_tile_count(saved_state) == 0
      assert File.exists?(target_path)
    end
  end

  describe "load orchestration" do
    test "load with missing file returns enoent" do
      assert SaveManager.load("/nonexistent/save/path.GAM") == {:error, :enoent}
    end

    test "load with empty path returns enoent" do
      assert SaveManager.load("") == {:error, :enoent}
      assert SaveManager.load(nil) == {:error, :enoent}
    end

    test "load initializes state with computed layers from valid save file" do
      dir = Path.join(System.tmp_dir!(), "load-test-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      path = Path.join(dir, "SAVE1.GAM")
      File.write!(path, :binary.copy(<<0>>, 0x20000))
      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:ok, state, loaded_path} = SaveManager.load(path)
      assert loaded_path == path
      assert state.save.path == path
      assert state.save_path == path
      assert state.active_layer == :terrain
      assert is_map(state.planes.arcanus)
      assert is_map(state.planes.myrror)
      assert Map.has_key?(state.planes.arcanus, :computed_adj_mask)
    end
  end

  describe "layer helpers" do
    test "default_selection maps all layers to 0" do
      selection = SaveManager.default_selection()
      assert selection[:terrain] == 0
      assert selection[:terrain_flags] == 0
      assert selection[:minerals] == 0
    end

    test "default_layer_visibility makes terrain and active layer visible" do
      vis = SaveManager.default_layer_visibility(:minerals)
      assert vis[:terrain] == true
      assert vis[:minerals] == true
      assert vis[:exploration] == false
    end

    test "ensure_layer_visible ensures both terrain and specified layer are true" do
      state = %{active_layer: :terrain, layer_visibility: %{terrain: true, minerals: false}}
      updated = SaveManager.ensure_layer_visible(state, :minerals)
      assert updated.layer_visibility[:terrain] == true
      assert updated.layer_visibility[:minerals] == true
    end

    test "normalize_phase_loop_status" do
      assert SaveManager.normalize_phase_loop_status(:detected) == :detected
      assert SaveManager.normalize_phase_loop_status("detected") == :detected
      assert SaveManager.normalize_phase_loop_status(:assumed) == :assumed
      assert SaveManager.normalize_phase_loop_status("assumed") == :assumed
      assert SaveManager.normalize_phase_loop_status(:other) == :unknown
    end
  end

  describe "engine session lifecycle" do
    test "engine_session_alive? returns false for nil" do
      refute SaveManager.engine_session_alive?(nil)
    end

    test "stop_engine_session returns :ok for nil" do
      assert SaveManager.stop_engine_session(nil) == :ok
    end

    test "restore_engine_session leaves state unchanged if not given a SaveFile" do
      state = %{engine_session_id: nil}
      assert SaveManager.restore_engine_session(state, nil) == state
    end
  end
end
