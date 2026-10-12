defmodule Mirror.NodeTerrainTest do
  use ExUnit.Case, async: true

  alias Mirror.Map, as: MMap
  alias Mirror.NodeTerrain

  @grass 162
  @forest 163
  @desert 165

  # A plane of one tile value everywhere (60 x 40, little-endian u16, as the editor holds it).
  defp plane(value), do: :binary.copy(<<value::little-16>>, 2400)

  defp put(terrain, x, y, value) do
    {updated, _} = MMap.put_tile_u16_le(terrain, x, y, value)
    updated
  end

  defp apply_edits(terrain, edits),
    do: Enum.reduce(edits, terrain, fn {x, y, v}, acc -> put(acc, x, y, v) end)

  defp tile(terrain, x, y), do: MMap.get_tile_u16_le(terrain, x, y)

  test "the new tile is the node and the old tile is land again" do
    # grass everywhere, with a Sorcery node (168) at (10, 10)
    terrain = plane(@grass) |> put(10, 10, 168)

    edits = NodeTerrain.edits(terrain, {10, 10}, {14, 12}, 168)
    moved = apply_edits(terrain, edits)

    assert tile(moved, 14, 12) == 168
    assert Mirror.TerrainType.terrain_type(tile(moved, 10, 10)) == :grass
    # nothing else changed
    changed = for x <- 0..59, y <- 0..39, tile(moved, x, y) != tile(terrain, x, y), do: {x, y}
    assert Enum.sort(changed) == [{10, 10}, {14, 12}]
  end

  test "the old tile takes the type the node moved onto (forest here), not just grass" do
    terrain = plane(@grass) |> put(10, 10, 169) |> put(14, 12, @forest)

    moved = NodeTerrain.edits(terrain, {10, 10}, {14, 12}, 169) |> then(&apply_edits(terrain, &1))
    assert tile(moved, 14, 12) == 169
    assert Mirror.TerrainType.terrain_type(tile(moved, 10, 10)) == :forest
  end

  test "a node moved onto desert leaves desert behind, with a tile that fits its neighbours" do
    # a desert world with a node in it, and a node moved onto desert elsewhere
    terrain = plane(@desert) |> put(10, 10, 170)

    moved = NodeTerrain.edits(terrain, {10, 10}, {20, 20}, 170) |> then(&apply_edits(terrain, &1))
    assert tile(moved, 20, 20) == 170
    assert Mirror.TerrainType.terrain_type(tile(moved, 10, 10)) == :desert
    # the old tile matches its desert neighbourhood, so no neighbour needed re-tiling
    changed = for x <- 0..59, y <- 0..39, tile(moved, x, y) != tile(terrain, x, y), do: {x, y}
    assert Enum.sort(changed) == [{10, 10}, {20, 20}]
  end

  test "which tiles a node may land on" do
    for tile <- [1, 163, 166, 165, 167, 171, 164], do: assert(NodeTerrain.can_land?(tile, 20))
    for tile <- [0, 2, 185, 18, 179, 168, 169, 170], do: refute(NodeTerrain.can_land?(tile, 20))
    for y <- [0, 1, 38, 39], do: refute(NodeTerrain.can_land?(1, y))
    assert :grass in NodeTerrain.land_types()
  end
end
