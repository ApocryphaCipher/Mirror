defmodule Mirror.EditorTest do
  use ExUnit.Case, async: true

  alias Mirror.Editor
  alias Mirror.SaveFile
  alias Mirror.TerrainPaint

  defp make_test_state do
    arcanus_terrain = :binary.copy(<<0::little-16>>, 2400)
    myrror_terrain = :binary.copy(<<10::little-16>>, 2400)

    arcanus_flags = :binary.copy(<<0>>, 2400)
    myrror_flags = :binary.copy(<<0>>, 2400)

    raw_planes = %{
      arcanus: %{terrain: arcanus_terrain, terrain_flags: arcanus_flags},
      myrror: %{terrain: myrror_terrain, terrain_flags: myrror_flags}
    }

    planes = Editor.with_computed_layers(raw_planes)

    save = %SaveFile{
      path: "/fake/SAVE1.GAM",
      planes: raw_planes,
      raw: <<>>
    }

    %{
      save: save,
      planes: planes,
      original_planes: raw_planes,
      active_layer: :terrain,
      selection: %{terrain: 5, terrain_flags: 1},
      history: %{arcanus: [], myrror: []},
      redo: %{arcanus: [], myrror: []},
      dataset_id: nil
    }
  end

  describe "coordinate and layer validation" do
    test "valid_coord? bounds" do
      assert Editor.valid_coord?(0, 0)
      assert Editor.valid_coord?(59, 39)
      refute Editor.valid_coord?(-1, 0)
      refute Editor.valid_coord?(0, -1)
      refute Editor.valid_coord?(60, 0)
      refute Editor.valid_coord?(0, 40)
      refute Editor.valid_coord?("0", 0)
    end

    test "layer types" do
      assert Editor.u16_layer?(:terrain)
      refute Editor.u16_layer?(:terrain_flags)
      assert Editor.u8_layer?(:terrain_flags)
      assert Editor.u8_layer?(:computed_adj_mask)
    end

    test "clamp_value" do
      assert Editor.clamp_value(:terrain, -5) == 0
      assert Editor.clamp_value(:terrain, 761) == 761
      assert Editor.clamp_value(:terrain, 999) == 761

      assert Editor.clamp_value(:terrain_flags, -1) == 0
      assert Editor.clamp_value(:terrain_flags, 255) == 255
      assert Editor.clamp_value(:terrain_flags, 300) == 255
    end
  end

  describe "plane computations and tile reading" do
    test "with_computed_layers and strip_computed" do
      planes = %{
        arcanus: %{terrain: :binary.copy(<<0::little-16>>, 2400)},
        myrror: %{terrain: :binary.copy(<<0::little-16>>, 2400)}
      }

      computed = Editor.with_computed_layers(planes)
      assert Map.has_key?(computed.arcanus, :computed_adj_mask)
      assert byte_size(computed.arcanus.computed_adj_mask) == 2400

      stripped = Editor.strip_computed(computed)
      refute Map.has_key?(stripped.arcanus, :computed_adj_mask)
    end

    test "tile_value and original_tile_value" do
      state = make_test_state()
      assert Editor.tile_value(state, :arcanus, :terrain, 0, 0) == 0
      assert Editor.tile_value(state, :myrror, :terrain, 0, 0) == 10
      assert Editor.original_tile_value(state, :arcanus, :terrain, 0, 0) == 0
      assert Editor.tile_value(state, :arcanus, :terrain, -1, 0) == nil
    end

    test "changed_tile_count" do
      state = make_test_state()
      assert Editor.changed_tile_count(state) == 0

      {updated_state, _change, _updates} =
        Editor.apply_tile(state, :arcanus, :terrain, 5, 5, 42)

      assert Editor.changed_tile_count(updated_state) == 1
    end
  end

  describe "state transitions" do
    test "apply_tile rejects invalid coords and computed_adj_mask" do
      state = make_test_state()

      {same_state, change, updates} =
        Editor.apply_tile(state, :arcanus, :computed_adj_mask, 0, 0, 1)

      assert change == nil
      assert updates == []
      assert same_state == state

      {same_state, change, updates} = Editor.apply_tile(state, :arcanus, :terrain, -1, 0, 1)
      assert change == nil
      assert updates == []
      assert same_state == state
    end

    test "apply_tile updates plane, save, and computed_adj_mask for terrain" do
      state = make_test_state()

      {updated_state, change, updates} =
        Editor.apply_tile(state, :arcanus, :terrain, 10, 10, 20)

      assert change == {0, 20}
      assert updates == [%{x: 10, y: 10, value: 20}]
      assert Editor.tile_value(updated_state, :arcanus, :terrain, 10, 10) == 20
      assert Editor.original_tile_value(updated_state, :arcanus, :terrain, 10, 10) == 0
      refute Map.has_key?(updated_state.save.planes.arcanus, :computed_adj_mask)
    end

    test "start_stroke on matching tile creates empty stroke; drag records :new on first difference" do
      state = make_test_state()
      # Tile at (0, 0) is already 0. Starting a stroke with 0 creates empty stroke.
      {state, stroke, change, updates} =
        Editor.start_stroke(state, :arcanus, :terrain, 0, 0, 0)

      assert Map.take(stroke, [:layer, :changes]) == %{layer: :terrain, changes: %{}}
      assert is_integer(stroke[:id])
      assert change == nil
      assert updates == []
      assert state.history.arcanus == []

      # Drag to (1, 0) painting 5
      {state, stroke, change, updates} =
        Editor.apply_stroke_change(state, stroke, :arcanus, :terrain, 1, 0, 5)

      assert change == {0, 5}
      assert updates == [%{x: 1, y: 0, value: 5}]
      assert stroke.changes == %{{1, 0} => {0, 5}}
      assert length(state.history.arcanus) == 1
      assert hd(state.history.arcanus).changes == [{1, 0, 0, 5}]

      # Drag to (2, 0) painting 5 updates head of history (:update mode)
      {state, stroke, change, _updates} =
        Editor.apply_stroke_change(state, stroke, :arcanus, :terrain, 2, 0, 5)

      assert change == {0, 5}
      assert map_size(stroke.changes) == 2
      assert length(state.history.arcanus) == 1
      assert length(hd(state.history.arcanus).changes) == 2
    end

    test "undo and redo cycle edits correctly" do
      state = make_test_state()

      {state, stroke, _change, _updates} =
        Editor.start_stroke(state, :arcanus, :terrain, 5, 5, 25)

      {state, _stroke, _change, _updates} =
        Editor.apply_stroke_change(state, stroke, :arcanus, :terrain, 6, 5, 25)

      assert Editor.tile_value(state, :arcanus, :terrain, 5, 5) == 25
      assert Editor.tile_value(state, :arcanus, :terrain, 6, 5) == 25
      assert Editor.changed_tile_count(state) == 2
      assert length(state.history.arcanus) == 1
      assert state.redo.arcanus == []

      # Undo
      {undone_state, {:applied, updates, layer, changes}} = Editor.undo(state, :arcanus)
      assert layer == :terrain
      assert length(updates) == 2
      assert length(changes) == 2
      assert Editor.tile_value(undone_state, :arcanus, :terrain, 5, 5) == 0
      assert Editor.tile_value(undone_state, :arcanus, :terrain, 6, 5) == 0
      assert Editor.changed_tile_count(undone_state) == 0
      assert undone_state.history.arcanus == []
      assert length(undone_state.redo.arcanus) == 1

      # Redo
      {redone_state, {:applied, updates, layer, changes}} = Editor.redo(undone_state, :arcanus)
      assert layer == :terrain
      assert length(updates) == 2
      assert length(changes) == 2
      assert Editor.tile_value(redone_state, :arcanus, :terrain, 5, 5) == 25
      assert Editor.tile_value(redone_state, :arcanus, :terrain, 6, 5) == 25
      assert Editor.changed_tile_count(redone_state) == 2
      assert length(redone_state.history.arcanus) == 1
      assert redone_state.redo.arcanus == []
    end

    test "apply_single_tile records to history and clears redo" do
      state = make_test_state()

      {state, {:applied, stroke, updates}} =
        Editor.apply_single_tile(state, :arcanus, :terrain_flags, 3, 3, 7)

      assert Map.take(stroke, [:layer, :changes]) == %{
               layer: :terrain_flags,
               changes: [{3, 3, 0, 7}]
             }

      assert is_integer(stroke[:id])
      assert updates == [%{x: 3, y: 3, value: 7}]
      assert length(state.history.arcanus) == 1
      assert Editor.tile_value(state, :arcanus, :terrain_flags, 3, 3) == 7

      # Undo single tile
      {undone_state, {:applied, _updates, _layer, _changes}} = Editor.undo(state, :arcanus)
      assert Editor.tile_value(undone_state, :arcanus, :terrain_flags, 3, 3) == 0
    end

    test "concurrent stroke continuation preserves interleaved stroke from another tab (STORY-043)" do
      state = make_test_state()

      # Tab A starts a drag stroke on Arcanus at (1, 1)
      {state, stroke_a, _change, _updates} =
        Editor.start_stroke(state, :arcanus, :terrain, 1, 1, 10)

      # Tab A continues drag to (1, 2)
      {state, stroke_a, _change, _updates} =
        Editor.apply_stroke_change(state, stroke_a, :arcanus, :terrain, 1, 2, 10)

      # Tab B commits a separate single-tile stroke in between at (5, 5)
      {state, stroke_b, _change, _updates} =
        Editor.start_stroke(state, :arcanus, :terrain, 5, 5, 20)

      assert length(state.history.arcanus) == 2
      assert hd(state.history.arcanus).id == stroke_b.id

      # Tab A continues drag to (1, 3)
      {state, _stroke_a, _change, _updates} =
        Editor.apply_stroke_change(state, stroke_a, :arcanus, :terrain, 1, 3, 10)

      # Tab B's stroke must remain at the head of history and not be clobbered
      assert length(state.history.arcanus) == 2
      assert hd(state.history.arcanus).id == stroke_b.id

      # Undoing once removes only Tab B's tile (5, 5), leaving Tab A's drag intact
      {undone_b, _} = Editor.undo(state, :arcanus)
      assert Editor.tile_value(undone_b, :arcanus, :terrain, 5, 5) == 0
      assert Editor.tile_value(undone_b, :arcanus, :terrain, 1, 1) == 10
      assert Editor.tile_value(undone_b, :arcanus, :terrain, 1, 2) == 10
      assert Editor.tile_value(undone_b, :arcanus, :terrain, 1, 3) == 10

      # Undoing a second time removes Tab A's whole drag
      {undone_a, _} = Editor.undo(undone_b, :arcanus)
      assert Editor.tile_value(undone_a, :arcanus, :terrain, 1, 1) == 0
      assert Editor.tile_value(undone_a, :arcanus, :terrain, 1, 2) == 0
      assert Editor.tile_value(undone_a, :arcanus, :terrain, 1, 3) == 0
    end

    test "discard restores planes and clears history and redo" do
      state = make_test_state()

      {state, _stroke, _change, _updates} =
        Editor.start_stroke(state, :arcanus, :terrain, 1, 1, 99)

      assert Editor.changed_tile_count(state) == 1

      {discarded_state, restored_save} = Editor.discard(state)
      assert Editor.changed_tile_count(discarded_state) == 0
      assert Editor.tile_value(discarded_state, :arcanus, :terrain, 1, 1) == 0
      assert discarded_state.history == %{arcanus: [], myrror: []}
      assert discarded_state.redo == %{arcanus: [], myrror: []}
      assert restored_save.planes == state.original_planes
    end
  end

  describe "compound edits and painting a type (STORY-017)" do
    alias Mirror.Landmass
    alias Mirror.Map, as: MMap

    defp make_paint_state do
      ocean = :binary.copy(<<0::little-16>>, 2400)
      zeros = :binary.copy(<<0>>, 2400)
      layers = %{terrain: ocean, terrain_flags: zeros, landmass: zeros}
      raw_planes = %{arcanus: layers, myrror: layers}

      %{
        save: %SaveFile{path: "/fake/SAVE1.GAM", planes: raw_planes, raw: <<>>},
        planes: Editor.with_computed_layers(raw_planes),
        original_planes: raw_planes,
        active_layer: :terrain,
        selection: %{terrain: 0},
        history: %{arcanus: [], myrror: []},
        redo: %{arcanus: [], myrror: []},
        dataset_id: nil
      }
    end

    defp layer(state, plane, name), do: state.planes[plane][name]

    defp landmass_ids(state, plane) do
      bin = layer(state, plane, :landmass)

      for y <- 0..39, x <- 0..59, id = MMap.get_tile_u8(bin, x, y), id != 0, do: {{x, y}, id}
    end

    test "apply_compound records one history step covering both layers" do
      state = make_paint_state()

      {state, {:applied, entry, layers}} =
        Editor.apply_compound(state, :arcanus, [
          {:terrain, [{5, 5, 162}, {6, 5, 162}]},
          {:landmass, [{5, 5, 3}, {6, 5, 3}]}
        ])

      assert length(state.history.arcanus) == 1
      assert entry.layer == :terrain
      assert [%{layer: :landmass}] = entry.also
      assert Enum.map(layers, & &1.layer) == [:terrain, :landmass]
      assert Editor.tile_value(state, :arcanus, :terrain, 5, 5) == 162
      assert Editor.tile_value(state, :arcanus, :landmass, 6, 5) == 3
    end

    test "apply_compound with nothing to change is :none and leaves history alone" do
      state = make_paint_state()

      assert {^state, :none} =
               Editor.apply_compound(state, :arcanus, [
                 {:terrain, [{5, 5, 0}]},
                 {:landmass, [{5, 5, 0}]}
               ])
    end

    test "one undo reverts every layer, one redo restores them, and the shapes carry the extras" do
      base = make_paint_state()

      {state, _} =
        Editor.apply_compound(base, :arcanus, [
          {:terrain, [{5, 5, 162}]},
          {:landmass, [{5, 5, 3}]}
        ])

      {undone, {:applied, updates, :terrain, changes, [extra]}} = Editor.undo(state, :arcanus)
      assert updates == [%{x: 5, y: 5, value: 0}]
      assert changes == [{5, 5, 162, 0}]

      assert %{layer: :landmass, updates: [%{x: 5, y: 5, value: 0}], changes: [{5, 5, 3, 0}]} =
               extra

      assert layer(undone, :arcanus, :terrain) == layer(base, :arcanus, :terrain)
      assert layer(undone, :arcanus, :landmass) == layer(base, :arcanus, :landmass)
      assert undone.history.arcanus == [] and length(undone.redo.arcanus) == 1

      {redone, {:applied, _, :terrain, _, [extra]}} = Editor.redo(undone, :arcanus)
      assert extra.layer == :landmass
      assert layer(redone, :arcanus, :terrain) == layer(state, :arcanus, :terrain)
      assert layer(redone, :arcanus, :landmass) == layer(state, :arcanus, :landmass)
    end

    test "single-layer steps keep the four-element undo result" do
      state = make_paint_state()
      {state, {:applied, _, _}} = Editor.apply_single_tile(state, :arcanus, :terrain, 1, 1, 7)
      assert {_, {:applied, _updates, :terrain, _changes}} = Editor.undo(state, :arcanus)
    end

    test "paint_type paints, re-tiles and numbers the new landmass in one undo step" do
      base = make_paint_state()
      cells = TerrainPaint.brush_cells(30, 20, 3)

      {state, {:applied, _entry, layers}, report} =
        Editor.paint_type(base, :arcanus, cells, :grass)

      assert report.skipped == [] and report.unresolved == [] and report.stale == []
      assert Enum.map(layers, & &1.layer) == [:terrain, :landmass]
      assert length(state.history.arcanus) == 1

      # a 3x3 island: nine tiles with one non-zero ID; shore cells and sea stay 0
      ids = landmass_ids(state, :arcanus)
      assert length(ids) == 9
      assert ids |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 1

      # the whole result follows the landmass rule
      terrain = Map.new([:arcanus, :myrror], &{&1, layer(state, &1, :terrain)})
      landmass = Map.new([:arcanus, :myrror], &{&1, layer(state, &1, :landmass)})
      assert Landmass.violations(terrain, landmass) == []

      # the other plane is untouched
      assert state.planes.myrror == base.planes.myrror

      # one undo gives back both layers exactly
      {undone, {:applied, _, :terrain, _, [_]}} = Editor.undo(state, :arcanus)
      assert undone.planes == base.planes
      assert Editor.changed_tile_count(undone) == 0
    end

    test "painting a bridge joins two landmasses under one ID, and undo splits them again" do
      base = make_paint_state()

      {state, _, _} =
        Editor.paint_type(base, :arcanus, TerrainPaint.brush_cells(10, 20, 3), :grass)

      {state, _, _} =
        Editor.paint_type(state, :arcanus, TerrainPaint.brush_cells(18, 20, 3), :grass)

      assert state.planes.arcanus.landmass
             |> :binary.bin_to_list()
             |> Enum.reject(&(&1 == 0))
             |> Enum.uniq()
             |> length() == 2

      {joined, {:applied, _entry, _layers}, report} =
        Editor.paint_type(state, :arcanus, for(x <- 12..16, do: {x, 20}), :grass)

      assert report.unresolved == []

      assert joined.planes.arcanus.landmass
             |> :binary.bin_to_list()
             |> Enum.reject(&(&1 == 0))
             |> Enum.uniq()
             |> length() == 1

      {split, {:applied, _, _, _, _}} = Editor.undo(joined, :arcanus)
      assert split.planes == state.planes
    end

    test "painting does not touch the other plane's landmass IDs" do
      base = make_paint_state()

      {state, _, _} =
        Editor.paint_type(base, :myrror, TerrainPaint.brush_cells(30, 20, 3), :grass)

      {state, _, _} =
        Editor.paint_type(state, :arcanus, TerrainPaint.brush_cells(30, 20, 3), :grass)

      arcanus = state |> landmass_ids(:arcanus) |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
      myrror = state |> landmass_ids(:myrror) |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
      assert [a] = arcanus
      assert [m] = myrror
      assert a != m
    end

    test "a paint that changes nothing is :none" do
      base = make_paint_state()

      assert {^base, :none, %{skipped: _, unresolved: _, stale: _}} =
               Editor.paint_type(base, :arcanus, [{10, 10}], :water)
    end

    test "running out of landmass IDs changes nothing and says so" do
      base = make_paint_state()
      islands = for x <- 0..58//2, y <- 2..36//2, do: {x, y}
      islands = Enum.take(islands, 255)

      grass =
        for {x, y} <- islands,
            reduce: layer(base, :arcanus, :terrain),
            do: (acc -> elem(MMap.put_tile_u16_le(acc, x, y, 162), 0))

      terrain = %{arcanus: grass, myrror: layer(base, :myrror, :terrain)}

      landmass0 = %{
        arcanus: layer(base, :arcanus, :landmass),
        myrror: layer(base, :myrror, :landmass)
      }

      {:ok, repaired} = Landmass.repair(terrain, landmass0)

      state = put_in(base, [:planes, :arcanus, :terrain], grass)
      state = put_in(state, [:planes, :arcanus, :landmass], repaired.arcanus)

      assert {^state, {:error, :out_of_ids}, _report} =
               Editor.paint_type(state, :arcanus, [{45, 20}], :grass)
    end

    test "a state without landmass data gets just the terrain change" do
      state = make_test_state()
      {state, {:applied, _, layers}, _} = Editor.paint_type(state, :arcanus, [{30, 20}], :grass)
      assert Enum.map(layers, & &1.layer) == [:terrain]
      assert Editor.tile_value(state, :arcanus, :terrain, 30, 20) == 162
    end
  end
end
