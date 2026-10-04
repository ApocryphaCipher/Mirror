defmodule Mirror.TerrainPaint do
  @moduledoc """
  Paint a terrain *type* (water, grass, forest, ...) onto cells and get back the
  tile numbers the game would have chosen, including the shore and edge tiles
  that change around the painted cells (STORY-017).

  Pure functions over a plane's terrain bytes (60x40 little-endian u16); the
  editor applies the returned changes.

  ## Model (checked against real maps, docs/reference/classic-terrain-format.md)

    * A cell is **water** (`:ocean`, `:shore`, `:lake`) or **land** (every other
      type). Painting chooses water or one land type for a cell.
    * Water splits into `:ocean` and `:shore` mechanically: a water cell is
      `:shore` if any of its 8 neighbours is land, otherwise `:ocean` (held for
      every one of 9,577 water cells on three fresh worlds). So painting land or
      water can turn neighbouring water cells between ocean and shore.
    * Only the painted cells and their 8 neighbours can change type. Beyond
      that, a cell's tile is re-picked **only if it no longer matches** its
      neighbourhood, and then to the first valid tile (`TerrainType.resolve_tile/2`).
      This is what the game does (a live Raise Volcano and Change Terrain, 10 of
      10 re-picked neighbours identical to the resolver's pick); neighbours that
      still match are left alone.
    * Off the north/south edge a direction is unconstrained, as in the tests.

  ## Not painted (reported as `skipped`)

  Rivers, lakes, the three node types and volcanoes, and the polar rows
  (0, 1, 38, 39). Their tiles have rules tied to each other (a river needs river
  or water neighbours) that this first version does not try to keep.

  Both planes store tile numbers 0..761, so resolution always uses `:arcanus`
  (`resolve_tile/2`'s `:myrror` adds kazzmir's combined-index offset, which a
  save does not use).
  """

  alias Mirror.Engine.Topology
  alias Mirror.Map, as: MMap
  alias Mirror.TerrainType

  @height 40
  @polar_rows [0, 1, 38, 39]
  @water [:ocean, :shore, :lake]
  @protected [:river, :lake, :chaos_node, :nature_node, :sorcery_node, :volcano]
  @land_kinds [:grass, :forest, :hill, :mountain, :desert, :swamp, :tundra]
  @kinds [:water | @land_kinds]

  # The game's own plain grass (4 variants appear in real maps: 162, 172, 173,
  # 180; it never uses tile 1, which the resolver would pick first).
  @preferred %{grass: 162}

  @type cell :: {integer(), integer()}
  @type change :: {integer(), integer(), integer(), integer()}
  @type result :: %{
          changes: [change()],
          skipped: [cell()],
          unresolved: [cell()],
          stale: [cell()]
        }

  @doc "The kinds that can be painted: `:water` and the plain land types."
  @spec kinds() :: [atom()]
  def kinds, do: @kinds

  @doc """
  Cells of a square brush of odd `size` (1, 3, 5, ...) centred on `{x, y}`;
  x wraps around the map, y is clipped at the poles.
  """
  @spec brush_cells(integer(), integer(), pos_integer()) :: [cell()]
  def brush_cells(x, y, size) when size >= 1 and rem(size, 2) == 1 do
    r = div(size - 1, 2)

    for dy <- -r..r,
        dx <- -r..r,
        ny = y + dy,
        ny in 0..(@height - 1),
        do: {MMap.wrap_x(x + dx), ny}
  end

  @doc """
  The connected cells (4-way, x wraps) that have the same kind as `{x, y}`:
  water (ocean and shore together) or one land type. Protected cells give `[]`.
  """
  @spec fill_cells(binary(), integer(), integer()) :: [cell()]
  def fill_cells(terrain, x, y) do
    kind = kind_of(type_at(terrain, %{}, {x, y}))

    if kind in @kinds do
      flood(terrain, kind, [{x, y}], MapSet.new([{x, y}]))
    else
      []
    end
  end

  defp flood(_terrain, _kind, [], seen),
    do: seen |> MapSet.to_list() |> Enum.sort_by(fn {x, y} -> {y, x} end)

  defp flood(terrain, kind, [{x, y} | rest], seen) do
    next =
      for {dx, dy} <- [{1, 0}, {-1, 0}, {0, 1}, {0, -1}],
          ny = y + dy,
          ny in 0..(@height - 1),
          cell = {MMap.wrap_x(x + dx), ny},
          not MapSet.member?(seen, cell),
          kind_of(type_at(terrain, %{}, cell)) == kind,
          do: cell

    flood(terrain, kind, next ++ rest, Enum.reduce(next, seen, &MapSet.put(&2, &1)))
  end

  @doc """
  Paints `kind` onto `cells` of `terrain`. Returns the tile changes
  (`{x, y, previous, new}`, ready for the editor's undo history) and what was
  not done:

    * `skipped`: painted cells left alone (protected type or polar row);
    * `unresolved`: painted cells no tile fits, so they were left unpainted;
    * `stale`: neighbours whose tile no longer matches but for which no tile fits
      either, left as they were.
  """
  @spec paint(binary(), [cell()], atom()) :: result()
  def paint(terrain, cells, kind) when kind in @kinds do
    {targets, skipped} = split_targets(terrain, Enum.uniq(cells), kind)
    run(terrain, targets, kind, skipped, [])
  end

  # Cells no tile fits are dropped and the paint is re-run without them, so the
  # result is always consistent for the cells that were painted.
  defp run(terrain, targets, kind, skipped, unresolved) do
    types = new_types(terrain, targets, kind)
    {changes, stale, bad} = tiles(terrain, types, targets)

    if bad == [] do
      %{
        changes: Enum.sort_by(changes, fn {x, y, _, _} -> {y, x} end),
        skipped: skipped,
        unresolved: unresolved,
        stale: stale
      }
    else
      run(terrain, targets -- bad, kind, skipped, unresolved ++ bad)
    end
  end

  defp split_targets(terrain, cells, kind) do
    Enum.reduce(cells, {[], []}, fn {_x, y} = cell, {ok, skipped} ->
      type = type_at(terrain, %{}, cell)

      cond do
        y in @polar_rows or type in @protected or type == nil -> {ok, [cell | skipped]}
        kind_of(type) == kind -> {ok, skipped}
        true -> {[cell | ok], skipped}
      end
    end)
    |> then(fn {ok, skipped} -> {Enum.reverse(ok), Enum.reverse(skipped)} end)
  end

  # The type of every cell whose type can change: the painted cells and their
  # 8 neighbours. Painted water starts as ocean and is settled below.
  defp new_types(terrain, targets, kind) do
    painted = Map.new(targets, &{&1, if(kind == :water, do: :ocean, else: kind)})
    ring = for cell <- targets, n <- neighbours(cell), do: n

    Enum.reduce(ring, painted, fn cell, acc ->
      Map.put_new_lazy(acc, cell, fn -> type_at(terrain, %{}, cell) end)
    end)
    |> settle_water(terrain)
  end

  # Water is :shore when any neighbour is land, otherwise :ocean (lakes stay lakes).
  defp settle_water(types, terrain) do
    Map.new(types, fn {cell, type} ->
      cond do
        type == :lake ->
          {cell, type}

        type in [:ocean, :shore] ->
          {cell, if(land_neighbour?(terrain, types, cell), do: :shore, else: :ocean)}

        true ->
          {cell, type}
      end
    end)
  end

  defp land_neighbour?(terrain, types, cell) do
    Enum.any?(neighbours(cell), fn n ->
      type_at(terrain, types, n) not in [nil | @water]
    end)
  end

  # Re-picks tiles over the painted cells and everything within 2 of them.
  defp tiles(terrain, types, targets) do
    check =
      for cell <- targets,
          dy <- -2..2,
          dx <- -2..2,
          ny = elem(cell, 1) + dy,
          ny in 0..(@height - 1),
          uniq: true,
          do: {MMap.wrap_x(elem(cell, 0) + dx), ny}

    painted = MapSet.new(targets)

    Enum.reduce(Enum.sort_by(check, fn {x, y} -> {y, x} end), {[], [], []}, fn {x, y} = cell,
                                                                               {changes, stale,
                                                                                bad} ->
      old = MMap.get_tile_u16_le(terrain, x, y)
      region = region(terrain, types, cell)
      type = Map.get(types, cell) || type_at(terrain, %{}, cell)
      is_painted = MapSet.member?(painted, cell)
      type_changed = type != type_at(terrain, %{}, cell)
      region = Map.put(region, :center, type)

      cond do
        not is_painted and not type_changed and TerrainType.matches?(old, region) ->
          {changes, stale, bad}

        true ->
          case pick(region, type) do
            nil when is_painted -> {changes, stale, [cell | bad]}
            nil -> {changes, [cell | stale], bad}
            ^old -> {changes, stale, bad}
            new -> {[{x, y, old, new} | changes], stale, bad}
          end
      end
    end)
  end

  defp pick(region, type) do
    preferred = Map.get(@preferred, type)

    if preferred && TerrainType.matches?(preferred, region) do
      preferred
    else
      TerrainType.resolve_tile(region, :arcanus)
    end
  end

  defp region(terrain, types, {x, y}) do
    Enum.reduce(0..7, %{}, fn dir, acc ->
      {dx, dy} = Topology.dir_delta(dir)

      case MMap.clamp_y(y + dy) do
        :off -> acc
        ny -> Map.put(acc, dir, type_at(terrain, types, {MMap.wrap_x(x + dx), ny}) || :unknown)
      end
    end)
  end

  defp neighbours({x, y}) do
    for dir <- 0..7,
        {dx, dy} = Topology.dir_delta(dir),
        ny = y + dy,
        ny in 0..(@height - 1),
        do: {MMap.wrap_x(x + dx), ny}
  end

  defp type_at(terrain, types, {x, y} = cell) do
    case Map.fetch(types, cell) do
      {:ok, type} -> type
      :error -> TerrainType.terrain_type(MMap.get_tile_u16_le(terrain, x, y))
    end
  end

  defp kind_of(type) when type in [:ocean, :shore], do: :water
  defp kind_of(type) when type in @land_kinds, do: type
  defp kind_of(type), do: type
end
