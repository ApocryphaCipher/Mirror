defmodule Mirror.TerrainTypeRetileTest do
  use ExUnit.Case, async: true

  # How the game re-tiles around a terrain change, from two live spells cast in
  # the real game (2026-10-04, docs/reference/classic-terrain-format.md, "How the
  # game re-tiles around a change"). Each patch is the tile numbers before and
  # after the cast, copied from the game's memory, so no save file is needed.
  #
  # The rule these tests pin down: a neighbour is re-picked only when its old
  # tile stopped matching, and the new tile is the one `resolve_tile/2` picks;
  # neighbours that still match are left alone.

  alias Mirror.TerrainType
  alias Mirror.Map, as: MMap
  alias Mirror.Engine.Topology

  # Raise Volcano on Arcanus (8,17): desert 306 -> volcano 179. Patch x 5..10, y 14..20.
  @volcano %{
    x0: 5,
    y0: 14,
    target: {8, 17},
    before: [
      [0, 10, 178, 171, 363, 237],
      [2, 39, 163, 436, 441, 237],
      [38, 377, 427, 390, 177, 254],
      [308, 177, 309, 306, 171, 237],
      [42, 373, 299, 306, 259, 189],
      [15, 85, 337, 331, 264, 184],
      [17, 308, 260, 262, 274, 184]
    ],
    after: [
      [0, 10, 178, 171, 363, 237],
      [2, 39, 163, 436, 441, 237],
      [38, 377, 428, 440, 177, 254],
      [308, 177, 368, 179, 171, 237],
      [42, 373, 322, 333, 259, 189],
      [15, 85, 337, 331, 264, 184],
      [17, 308, 260, 262, 274, 184]
    ]
  }

  # Change Terrain on Arcanus (41,15): desert 333 -> grass 162. Patch x 38..43, y 12..18.
  @change_terrain %{
    x0: 38,
    y0: 12,
    target: {41, 15},
    before: [
      [16, 382, 272, 271, 180, 162],
      [106, 415, 333, 264, 282, 279],
      [90, 313, 311, 265, 281, 184],
      [353, 299, 317, 333, 177, 178],
      [259, 337, 294, 331, 173, 36],
      [270, 267, 268, 171, 180, 131],
      [272, 270, 271, 163, 34, 100]
    ],
    after: [
      [16, 382, 272, 271, 180, 162],
      [106, 415, 333, 264, 282, 279],
      [90, 313, 306, 265, 281, 184],
      [353, 299, 311, 162, 177, 178],
      [259, 337, 402, 379, 173, 36],
      [270, 267, 268, 171, 180, 131],
      [272, 270, 271, 163, 34, 100]
    ]
  }

  describe "the patches" do
    test "contain the tiles the game really changed (guards against vacuous loops)" do
      assert length(changed(@volcano)) == 6
      assert length(changed(@change_terrain)) == 5
      assert length(unchanged(@volcano)) > 10
      assert length(unchanged(@change_terrain)) > 10
    end
  end

  describe "Raise Volcano" do
    test "changed neighbours were invalid and become exactly the resolver's pick" do
      for {x, y, old, new} <- changed(@volcano) do
        assert_retiled(@volcano, x, y, old, new)
        assert TerrainType.resolve_tile(region(@volcano, x, y), :arcanus) == new
      end
    end

    test "the volcano tile itself is type :volcano" do
      assert TerrainType.terrain_type(179) == :volcano
      {tx, ty} = @volcano.target
      assert tile(@volcano.after, @volcano, tx, ty) == 179
    end

    test "unchanged neighbours still match and are left alone" do
      for {x, y, old} <- unchanged(@volcano) do
        assert TerrainType.matches?(old, region(@volcano, x, y))
      end
    end
  end

  describe "Change Terrain" do
    test "changed neighbours were invalid and become exactly the resolver's pick" do
      {tx, ty} = @change_terrain.target

      for {x, y, old, new} <- changed(@change_terrain), {x, y} != {tx, ty} do
        assert_retiled(@change_terrain, x, y, old, new)
        assert TerrainType.resolve_tile(region(@change_terrain, x, y), :arcanus) == new
      end
    end

    test "the cast tile becomes a valid grass variant (any variant is acceptable)" do
      {tx, ty} = @change_terrain.target
      new = tile(@change_terrain.after, @change_terrain, tx, ty)

      assert TerrainType.terrain_type(new) == :grass
      assert TerrainType.matches?(new, region(@change_terrain, tx, ty))
      refute TerrainType.matches?(333, region(@change_terrain, tx, ty))
    end

    test "unchanged neighbours still match and are left alone" do
      for {x, y, old} <- unchanged(@change_terrain) do
        assert TerrainType.matches?(old, region(@change_terrain, x, y))
      end
    end
  end

  defp assert_retiled(patch, x, y, old, new) do
    region = region(patch, x, y)
    refute TerrainType.matches?(old, region), "tile #{old} at (#{x},#{y}) should no longer match"
    assert TerrainType.matches?(new, region), "tile #{new} at (#{x},#{y}) should match"
  end

  # Interior tiles only: those whose whole 3x3 neighbourhood is inside the patch.
  defp interior(patch) do
    rows = length(patch.after)
    cols = length(hd(patch.after))
    for dy <- 1..(rows - 2), dx <- 1..(cols - 2), do: {patch.x0 + dx, patch.y0 + dy}
  end

  defp changed(patch) do
    for {x, y} <- interior(patch),
        old = tile(patch.before, patch, x, y),
        new = tile(patch.after, patch, x, y),
        old != new,
        do: {x, y, old, new}
  end

  defp unchanged(patch) do
    for {x, y} <- interior(patch),
        old = tile(patch.before, patch, x, y),
        old == tile(patch.after, patch, x, y),
        do: {x, y, old}
  end

  defp tile(rows, patch, x, y), do: rows |> Enum.at(y - patch.y0) |> Enum.at(x - patch.x0)

  # The "after" plane: the patch dropped into an ocean plane (60x40 u16), so the
  # neighbourhood of every interior tile is the real one.
  defp region(patch, x, y) do
    plane =
      for py <- 0..(MMap.height() - 1), px <- 0..59, into: <<>> do
        t =
          if px in patch.x0..(patch.x0 + length(hd(patch.after)) - 1) and
               py in patch.y0..(patch.y0 + length(patch.after) - 1),
             do: tile(patch.after, patch, px, py),
             else: 0

        <<t::little-unsigned-16>>
      end

    build_region(plane, x, y)
  end

  # Same neighbour lookup the whole-save test uses (see terrain_type_test.exs).
  defp build_region(terrain_bin, x, y) do
    center = TerrainType.terrain_type(MMap.get_tile_u16_le(terrain_bin, x, y)) || :unknown

    Enum.reduce(0..7, %{center: center}, fn dir, acc ->
      {dx, dy} = Topology.dir_delta(dir)
      nx = MMap.wrap_x(x + dx)

      case MMap.clamp_y(y + dy) do
        :off ->
          acc

        ny ->
          Map.put(
            acc,
            dir,
            TerrainType.terrain_type(MMap.get_tile_u16_le(terrain_bin, nx, ny)) || :unknown
          )
      end
    end)
  end
end
