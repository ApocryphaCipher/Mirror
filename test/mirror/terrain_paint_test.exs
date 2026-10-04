defmodule Mirror.TerrainPaintTest do
  use ExUnit.Case, async: true

  alias Mirror.Engine.Topology
  alias Mirror.Map, as: MMap
  alias Mirror.{TerrainPaint, TerrainType}

  @ocean 0
  @river 185
  @lake 18
  @node 168

  defp ocean_plane, do: for(_ <- 1..(60 * 40), into: <<>>, do: <<@ocean::little-unsigned-16>>)

  defp apply_changes(bin, changes) do
    Enum.reduce(changes, bin, fn {x, y, _prev, new}, acc ->
      elem(MMap.put_tile_u16_le(acc, x, y, new), 0)
    end)
  end

  defp paint(bin, cells, kind) do
    result = TerrainPaint.paint(bin, cells, kind)
    {apply_changes(bin, result.changes), result}
  end

  defp type(bin, x, y), do: TerrainType.terrain_type(MMap.get_tile_u16_le(bin, x, y))

  defp region(bin, x, y) do
    Enum.reduce(0..7, %{center: type(bin, x, y)}, fn dir, acc ->
      {dx, dy} = Topology.dir_delta(dir)

      case MMap.clamp_y(y + dy) do
        :off -> acc
        ny -> Map.put(acc, dir, type(bin, MMap.wrap_x(x + dx), ny))
      end
    end)
  end

  defp invalid_cells(bin) do
    for y <- 0..39,
        x <- 0..59,
        not TerrainType.matches?(MMap.get_tile_u16_le(bin, x, y), region(bin, x, y)),
        do: {x, y}
  end

  # Water is :shore exactly when some neighbour is land.
  defp water_rule_violations(bin) do
    for y <- 0..39,
        x <- 0..59,
        type(bin, x, y) in [:ocean, :shore],
        has_land =
          Enum.any?(0..7, fn d ->
            Map.get(region(bin, x, y), d) not in [nil, :ocean, :shore, :lake]
          end),
        type(bin, x, y) == :shore != has_land,
        do: {x, y}
  end

  # A 9x9 grass island has its west coast at x = 26: cutting a bay into it at
  # x = 26 is a paint that resolves, with column 27 just inside the coast.
  defp island_with({x, y}, tile) do
    {grass, _} = paint(ocean_plane(), TerrainPaint.brush_cells(30, 20, 9), :grass)
    elem(MMap.put_tile_u16_le(grass, x, y, tile), 0)
  end

  describe "brush_cells/3" do
    test "odd square brushes centred on the cell" do
      assert TerrainPaint.brush_cells(10, 10, 1) == [{10, 10}]
      assert length(TerrainPaint.brush_cells(10, 10, 3)) == 9
      assert length(TerrainPaint.brush_cells(10, 10, 5)) == 25
    end

    test "x wraps around the map, y is clipped at the poles" do
      assert {59, 10} in TerrainPaint.brush_cells(0, 10, 3)
      assert length(TerrainPaint.brush_cells(10, 0, 3)) == 6
      assert Enum.all?(TerrainPaint.brush_cells(10, 39, 5), fn {_x, y} -> y in 37..39 end)
    end
  end

  describe "painting land into the sea" do
    test "one grass tile becomes a one-tile island with shore all round" do
      {map, result} = paint(ocean_plane(), [{30, 20}], :grass)

      assert result.skipped == [] and result.unresolved == [] and result.stale == []
      assert type(map, 30, 20) == :grass
      assert MMap.get_tile_u16_le(map, 30, 20) == 162

      for {dx, dy} <- [{-1, -1}, {0, -1}, {1, -1}, {-1, 0}, {1, 0}, {-1, 1}, {0, 1}, {1, 1}],
          do: assert(type(map, 30 + dx, 20 + dy) == :shore)

      assert type(map, 28, 20) == :ocean
      assert invalid_cells(map) == []
      assert water_rule_violations(map) == []
    end

    test "a bigger blob leaves a clean coastline and no invalid tiles" do
      {map, result} = paint(ocean_plane(), TerrainPaint.brush_cells(30, 20, 5), :grass)

      assert result.unresolved == [] and result.stale == []
      assert invalid_cells(map) == []
      assert water_rule_violations(map) == []
    end

    test "painting the same thing again changes nothing" do
      {map, _} = paint(ocean_plane(), TerrainPaint.brush_cells(30, 20, 3), :forest)

      assert %{changes: []} =
               TerrainPaint.paint(map, TerrainPaint.brush_cells(30, 20, 3), :forest)
    end

    test "changes record the previous tile, so they can be undone" do
      base = ocean_plane()
      {map, result} = paint(base, TerrainPaint.brush_cells(30, 20, 3), :grass)

      for {x, y, prev, new} <- result.changes do
        assert prev == MMap.get_tile_u16_le(base, x, y)
        assert new == MMap.get_tile_u16_le(map, x, y)
        assert prev != new
      end

      undone =
        Enum.reduce(result.changes, map, fn {x, y, prev, _}, acc ->
          elem(MMap.put_tile_u16_le(acc, x, y, prev), 0)
        end)

      assert undone == base
    end
  end

  describe "painting water into land" do
    setup do
      {map, _} = paint(ocean_plane(), TerrainPaint.brush_cells(30, 20, 9), :grass)
      %{map: map}
    end

    test "cutting a bay into the coast turns land cells into shore and re-tiles neighbours", %{
      map: map
    } do
      # the western edge of the 9x9 block is x = 26; carve into it
      {after_, result} = paint(map, [{26, 20}, {27, 20}], :water)

      assert result.unresolved == [] and result.stale == []
      assert type(after_, 26, 20) == :shore
      assert invalid_cells(after_) == []
      assert water_rule_violations(after_) == []
    end

    test "only tiles that stopped matching are re-picked (grass interior is untouched)", %{
      map: map
    } do
      {_after, result} = paint(map, [{26, 20}], :water)
      changed = MapSet.new(result.changes, fn {x, y, _, _} -> {x, y} end)

      # nothing further than 2 cells from the painted cell can change
      assert Enum.all?(changed, fn {x, y} -> abs(x - 26) <= 2 and abs(y - 20) <= 2 end)
      # the middle of the island does not change
      refute {30, 20} in changed
    end
  end

  describe "cells that are not painted" do
    test "rivers, lakes, nodes and volcanoes are skipped" do
      base = ocean_plane()

      base =
        Enum.reduce(
          [{10, 10, @river}, {12, 10, @lake}, {14, 10, @node}, {16, 10, 179}],
          base,
          fn {x, y, t}, acc -> elem(MMap.put_tile_u16_le(acc, x, y, t), 0) end
        )

      cells = [{10, 10}, {12, 10}, {14, 10}, {16, 10}]

      assert %{changes: [], skipped: skipped} = TerrainPaint.paint(base, cells, :grass)
      assert Enum.sort(skipped) == cells
    end

    test "the polar rows are skipped" do
      cells = [{10, 0}, {10, 1}, {10, 38}, {10, 39}]
      assert %{changes: [], skipped: skipped} = TerrainPaint.paint(ocean_plane(), cells, :grass)
      assert Enum.sort(skipped) == cells
    end

    test "a skipped cell in the brush is never changed, even beside a painted cell" do
      for {tile, name} <- [{@river, "river"}, {@lake, "lake"}, {@node, "node"}, {179, "volcano"}] do
        base = island_with({27, 20}, tile)
        {after_, result} = paint(base, [{26, 20}, {27, 20}], :water)

        assert {27, 20} in result.skipped, name
        assert MMap.get_tile_u16_le(after_, 27, 20) == tile, name
        refute Enum.any?(result.changes, fn {x, y, _, _} -> {x, y} == {27, 20} end), name
        assert type(after_, 26, 20) == :shore, name
      end
    end

    test "a skipped cell that stops matching is reported as stale, not fixed" do
      base = island_with({27, 20}, @river)
      {after_, result} = paint(base, [{26, 20}, {27, 20}], :water)

      newly_invalid =
        TerrainType.matches?(@river, region(base, 27, 20)) and
          not TerrainType.matches?(@river, region(after_, 27, 20))

      assert {27, 20} in result.stale == newly_invalid
    end

    test "polar-row cells in the brush are never changed" do
      # (30, 1) is a polar row, (30, 2) is paintable; land at (30, 2) means the
      # ocean tile above it no longer matches, yet it must not change.
      {after_, result} = paint(ocean_plane(), [{30, 1}, {30, 2}], :grass)

      assert {30, 1} in result.skipped
      assert MMap.get_tile_u16_le(after_, 30, 1) == @ocean
      assert {30, 1} in result.stale
      assert type(after_, 30, 2) == :grass
    end

    test "a protected cell that is only a neighbour of the brush may be re-tiled; if it still does not match it is reported" do
      base = island_with({27, 20}, @river)
      {after_, result} = paint(base, [{26, 20}], :water)

      refute {27, 20} in result.skipped
      new_tile = MMap.get_tile_u16_le(after_, 27, 20)
      matched_before = TerrainType.matches?(@river, region(base, 27, 20))

      # what changed is valid; what could not be fixed and used to match is reported
      assert TerrainType.matches?(new_tile, region(after_, 27, 20)) or
               not matched_before or {27, 20} in result.stale
    end

    test "a cell that already has the requested kind is a no-op, not skipped" do
      assert %{changes: [], skipped: []} = TerrainPaint.paint(ocean_plane(), [{10, 10}], :water)
    end
  end

  describe "fill_cells/3" do
    test "fills the connected cells of the same kind, leaving out protected cells" do
      {map, _} = paint(ocean_plane(), TerrainPaint.brush_cells(30, 20, 5), :grass)

      island = TerrainPaint.fill_cells(map, 30, 20)
      assert length(island) == 25
      # the sea is everything else except the 4 polar rows (4 * 60 cells)
      sea = TerrainPaint.fill_cells(map, 10, 10)
      assert length(sea) == 2400 - 25 - 4 * 60
      refute Enum.any?(sea, fn {_x, y} -> y in [0, 1, 38, 39] end)
    end

    test "a seed in a polar row fills nothing, even on an all-ocean plane" do
      for seed <- [{0, 0}, {10, 1}, {59, 38}, {30, 39}] do
        assert TerrainPaint.fill_cells(ocean_plane(), elem(seed, 0), elem(seed, 1)) == []
      end
    end

    test "a seed off the map fills nothing" do
      assert TerrainPaint.fill_cells(ocean_plane(), 60, 10) == []
      assert TerrainPaint.fill_cells(ocean_plane(), 10, -1) == []
    end

    test "a protected cell fills nothing" do
      {map, _} = {elem(MMap.put_tile_u16_le(ocean_plane(), 5, 5, @river), 0), nil}
      assert TerrainPaint.fill_cells(map, 5, 5) == []
    end
  end

  describe "the grass variant" do
    test "plain grass is the game's tile 162, not the resolver's first match (tile 1)" do
      {map, _} = paint(ocean_plane(), [{30, 20}], :grass)
      assert MMap.get_tile_u16_le(map, 30, 20) == 162
    end
  end

  @mom_path System.get_env("MIRROR_MOM_PATH")
  @save1 @mom_path && Path.join(@mom_path, "SAVE1.GAM")

  describe "on a real map" do
    @tag skip: !(@save1 && File.exists?(@save1)) && "needs SAVE1.GAM"
    test "random brushes keep the map consistent, and everything unfixable is reported" do
      {:ok, save} = Mirror.SaveFile.load(@save1)
      :rand.seed(:exsss, {1, 2, 3})

      for plane <- [:arcanus, :myrror] do
        base = save.planes[plane].terrain
        base_invalid = MapSet.new(invalid_cells(base))
        assert water_rule_violations(base) == []

        for _ <- 1..60 do
          kind = Enum.random(TerrainPaint.kinds())

          cells =
            TerrainPaint.brush_cells(
              :rand.uniform(60) - 1,
              :rand.uniform(40) - 1,
              Enum.random([1, 3, 5])
            )

          {map, result} = paint(base, cells, kind)

          painted = cells -- (result.skipped ++ result.unresolved)

          for {x, y} <- painted do
            t = type(map, x, y)
            if kind == :water, do: assert(t in [:ocean, :shore]), else: assert(t == kind)
          end

          assert water_rule_violations(map) == []
          # every newly invalid tile is one we reported as stale
          new_invalid = MapSet.difference(MapSet.new(invalid_cells(map)), base_invalid)
          assert MapSet.subset?(new_invalid, MapSet.new(result.stale))
          assert %{changes: []} = TerrainPaint.paint(map, cells, kind)
        end
      end
    end
  end
end
