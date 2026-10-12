defmodule Mirror.NodeTerrain do
  @moduledoc """
  The map edits that go with moving a magic node (STORY-019): a node is its terrain tile, so the
  old tile has to become ordinary land again and the new tile has to become the node.

  Pure functions over a plane's terrain bytes (`Mirror.TerrainPaint`'s 60x40 little-endian u16).

  * The new tile becomes the node tile (168 Sorcery, 169 Nature, 170 Chaos). Its neighbours are
    **not** re-tiled: the game never does, and as far as they can tell the land is still what
    it was.
  * The old tile becomes the same *type* of land the node moved onto, with the variant
    that fits its own neighbours, picked by `Mirror.TerrainPaint` (which also re-tiles
    a neighbour only if it no longer matches). If no tile fits, it becomes plain grass.
  * What a node can move onto: grassland, forest, swamp, desert, tundra, hills and mountains,
    outside the polar rows. Not water, a river, a lake, a volcano or another node: those are
    protected the way the type painter protects them.
  """

  alias Mirror.Map, as: MMap
  alias Mirror.{TerrainPaint, TerrainType}

  @land [:grass, :forest, :hill, :mountain, :desert, :swamp, :tundra]
  @polar_rows [0, 1, 38, 39]
  @plain_grass 162

  @doc "The terrain types a node may be moved onto."
  def land_types, do: @land

  @doc "True when a node may be put on the tile `value` at row `y`."
  @spec can_land?(integer(), integer()) :: boolean()
  def can_land?(value, y), do: y not in @polar_rows and TerrainType.terrain_type(value) in @land

  @doc """
  The terrain changes `{x, y, value}` for moving the node whose tile is at `from` to `to`, whose
  tile is `node_tile`. Nothing is returned for a tile that ends up as it was.
  """
  @spec edits(binary(), {integer(), integer()}, {integer(), integer()}, integer()) :: [
          {integer(), integer(), integer()}
        ]
  def edits(terrain, {fx, fy} = from, {tx, ty} = to, node_tile) do
    kind = TerrainType.terrain_type(MMap.get_tile_u16_le(terrain, tx, ty))

    # The node's own tile is protected, so paint over a plain one in a copy.
    {with_placeholder, _old} = MMap.put_tile_u16_le(terrain, fx, fy, 1)
    result = TerrainPaint.paint(with_placeholder, [from], kind)

    {painted, from_value} =
      if from in result.skipped or from in result.unresolved do
        {changed, _} = MMap.put_tile_u16_le(with_placeholder, fx, fy, @plain_grass)
        {changed, @plain_grass}
      else
        painted = apply_changes(with_placeholder, result.changes)
        {painted, MMap.get_tile_u16_le(painted, fx, fy)}
      end

    _ = from_value

    # Every tile the paint touched, plus the node's old tile, compared with the real terrain.
    touched = [from | for({x, y, _prev, _new} <- result.changes, do: {x, y})]

    changed =
      for {x, y} <- Enum.uniq(touched),
          {x, y} != to,
          new = MMap.get_tile_u16_le(painted, x, y),
          new != MMap.get_tile_u16_le(terrain, x, y),
          do: {x, y, new}

    changed ++ [{tx, ty, node_tile}]
  end

  defp apply_changes(terrain, changes) do
    Enum.reduce(changes, terrain, fn {x, y, _prev, new}, acc ->
      {updated, _} = MMap.put_tile_u16_le(acc, x, y, new)
      updated
    end)
  end
end
