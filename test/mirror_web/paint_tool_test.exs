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

    test "a paint that had to repair far more landmass IDs than it changed tiles says so" do
      assert {:warn, text} = PaintTool.summary(report(), 1, 2160)
      assert text =~ "1 tile changed"
      assert text =~ "landmass layer repaired on 2160 tiles"

      # an ordinary paint touches about as many IDs as tiles: no note
      assert {:ok, "9 tiles changed"} = PaintTool.summary(report(), 9, 1)
      assert {:ok, "9 tiles changed"} = PaintTool.summary(report(), 9, 9)
    end

    test "works with sets as well as lists" do
      assert {:warn, text} = PaintTool.summary(report(MapSet.new([{1, 1}])), 0)
      assert text =~ "0 tiles changed"
      assert text =~ "1 left alone"
    end
  end
end
