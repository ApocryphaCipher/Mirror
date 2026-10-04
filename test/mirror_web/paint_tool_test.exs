defmodule MirrorWeb.PaintToolTest do
  use ExUnit.Case, async: true

  alias Mirror.{TerrainPaint, TerrainType}
  alias MirrorWeb.PaintTool

  describe "options" do
    test "the terrain dropdown offers every paintable kind, and each value parses back" do
      values = Enum.map(PaintTool.kind_options(), &elem(&1, 1))

      assert Enum.sort(Enum.map(values, &PaintTool.parse_kind/1)) ==
               Enum.sort(TerrainPaint.kinds())

      assert {"Water (ocean)", "water"} in PaintTool.kind_options()
    end

    test "the brush sizes are 1, 3 and 5" do
      assert PaintTool.size_options() == [{"1 × 1", "1"}, {"3 × 3", "3"}, {"5 × 5", "5"}]
    end

    test "each quick-pick tile is really the terrain its label says" do
      expected = %{
        "Ocean" => :ocean,
        "Grassland" => :grass,
        "Forest" => :forest,
        "Hills" => :hill,
        "Mountains" => :mountain,
        "Desert" => :desert,
        "Swamp" => :swamp,
        "Tundra" => :tundra
      }

      for {label, tile} <- PaintTool.quick_tile_options() do
        assert TerrainType.terrain_type(tile) == Map.fetch!(expected, label), label
      end

      assert length(PaintTool.quick_tile_options()) == map_size(expected)
    end
  end

  describe "parsing" do
    test "unknown or unpaintable kinds are rejected" do
      assert PaintTool.parse_kind("grass") == :grass
      assert PaintTool.parse_kind("river") == nil
      assert PaintTool.parse_kind("lake") == nil
      assert PaintTool.parse_kind("") == nil
      assert PaintTool.parse_kind(nil) == nil
    end

    test "sizes other than 1, 3, 5 fall back to the default" do
      assert PaintTool.parse_size("3") == 3
      assert PaintTool.parse_size("5") == 5
      assert PaintTool.parse_size("4") == 1
      assert PaintTool.parse_size("999") == 1
      assert PaintTool.parse_size("x") == 1
      assert PaintTool.parse_size(nil, 3) == 3
    end

    test "checkbox values" do
      assert PaintTool.parse_flag("true") and PaintTool.parse_flag("on")

      refute PaintTool.parse_flag("false") or PaintTool.parse_flag(nil) or
               PaintTool.parse_flag("")
    end
  end

  describe "the eyedropper" do
    test "open water is water, plain land is itself, everything else cannot be painted" do
      assert PaintTool.kind_of_type(:ocean) == :water
      assert PaintTool.kind_of_type(:shore) == :water
      assert PaintTool.kind_of_type(:forest) == :forest
      assert PaintTool.kind_of_type(:tundra) == :tundra

      for t <- [:river, :lake, :sorcery_node, :nature_node, :chaos_node, :volcano, nil],
          do: assert(PaintTool.kind_of_type(t) == nil)
    end
  end

  describe "summary/2" do
    defp report(skipped \\ [], unresolved \\ [], stale \\ []),
      do: %{skipped: skipped, unresolved: unresolved, stale: stale}

    test "a clean paint is just the count" do
      assert {:ok, "1 tile changed"} = PaintTool.summary(report(), 1)
      assert {:ok, "12 tiles changed"} = PaintTool.summary(report(), 12)
    end

    test "each problem adds a plain sentence and makes it a warning" do
      assert {:warn, text} =
               PaintTool.summary(report([{1, 1}, {2, 2}], [{3, 3}], [{4, 4}, {5, 5}, {6, 6}]), 9)

      assert text =~ "9 tiles changed"
      assert text =~ "2 left alone (river, lake, node, volcano or polar row)"
      assert text =~ "1 left as they were: no tile fits that shape of coastline"
      assert text =~ "3 neighbouring tiles may not match"
    end

    test "a paint that had to repair an out-of-step landmass layer says so" do
      assert {:warn, text} = PaintTool.summary(report(), 1, 2160)
      assert text =~ "1 tile changed"
      assert text =~ "landmass layer repaired on 2160 tiles"
    end

    test "an ordinary paint says nothing about the landmass layer, however many IDs it renumbered" do
      assert {:ok, "9 tiles changed"} = PaintTool.summary(report(), 9)
      assert {:ok, "9 tiles changed"} = PaintTool.summary(report(), 9, 0)
    end

    test "works with sets as well as lists" do
      assert {:warn, text} = PaintTool.summary(report(MapSet.new([{1, 1}])), 0)
      assert text =~ "0 tiles changed"
      assert text =~ "1 left alone"
    end
  end

  describe "the running report over a drag" do
    alias Mirror.Map, as: MMap

    defp ocean, do: :binary.copy(<<0, 0>>, 2400)
    defp put(terrain, x, y, tile), do: elem(MMap.put_tile_u16_le(terrain, x, y, tile), 0)

    defp step_report(opts \\ []),
      do:
        Map.merge(
          %{skipped: [], unresolved: [], stale: [], landmass_out_of_step: false},
          Map.new(opts)
        )

    test "starts empty" do
      r = PaintTool.new_report()
      assert MapSet.size(r.touched) == 0 and r.landmass == 0
    end

    test "a cell a drag crosses twice is counted once" do
      r =
        PaintTool.merge_report(
          PaintTool.new_report(),
          step_report(),
          [{1, 1}, {2, 1}],
          0,
          ocean()
        )

      r = PaintTool.merge_report(r, step_report(), [{2, 1}, {3, 1}], 0, ocean())
      assert MapSet.size(r.touched) == 3
    end

    test "a stale cell that a later step re-tiled stops warning" do
      # (10, 10) holds a shore tile that does not fit an all-ocean neighbourhood
      broken = put(ocean(), 10, 10, 2)

      r =
        PaintTool.merge_report(
          PaintTool.new_report(),
          step_report(stale: [{10, 10}]),
          [],
          0,
          broken
        )

      assert MapSet.member?(r.stale, {10, 10})

      # a later step fixes it (the tile is plain ocean again)
      r = PaintTool.merge_report(r, step_report(), [{10, 10}], 0, ocean())
      refute MapSet.member?(r.stale, {10, 10})
    end

    test "a stale cell also stops warning when a neighbour's change makes its tile fit again" do
      broken = put(ocean(), 10, 10, 2)

      r =
        PaintTool.merge_report(
          PaintTool.new_report(),
          step_report(stale: [{10, 10}]),
          [],
          0,
          broken
        )

      # the cell itself did not change, but the terrain now fits it (it is not in changed_cells)
      r = PaintTool.merge_report(r, step_report(), [{11, 10}], 0, ocean())
      assert MapSet.size(r.stale) == 0
    end

    test "a stale cell that is still wrong keeps warning" do
      broken = put(ocean(), 10, 10, 2)

      r =
        PaintTool.merge_report(
          PaintTool.new_report(),
          step_report(stale: [{10, 10}]),
          [],
          0,
          broken
        )

      r = PaintTool.merge_report(r, step_report(), [{30, 30}], 0, broken)
      assert MapSet.member?(r.stale, {10, 10})
    end

    test "an unresolved cell that a later step painted drops out; skipped cells stay" do
      r =
        PaintTool.merge_report(
          PaintTool.new_report(),
          step_report(unresolved: [{5, 5}], skipped: [{6, 6}]),
          [],
          0,
          ocean()
        )

      assert MapSet.member?(r.unresolved, {5, 5})

      r = PaintTool.merge_report(r, step_report(), [{5, 5}], 0, ocean())
      refute MapSet.member?(r.unresolved, {5, 5})
      assert MapSet.member?(r.skipped, {6, 6})
    end

    test "landmass changes are counted only when the layer was out of step before the paint" do
      r =
        PaintTool.merge_report(
          PaintTool.new_report(),
          step_report(landmass_out_of_step: false),
          [],
          500,
          ocean()
        )

      assert r.landmass == 0

      r = PaintTool.merge_report(r, step_report(landmass_out_of_step: true), [], 2160, ocean())
      assert r.landmass == 2160
    end
  end
end
