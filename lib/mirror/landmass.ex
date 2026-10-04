defmodule Mirror.Landmass do
  @moduledoc """
  The landmass ("continent") layer: one byte per tile saying which landmass a
  tile belongs to. Pure functions over terrain and landmass bytes, so an editor
  can keep the layer consistent after terrain edits.

  ## The rule

  Decoded from fresh maps and saves (docs/reference/classic-terrain-format.md,
  "Landmass layer"); it held on every valid map checked (12 distinct maps, both
  planes):

    * a tile is **land** unless its type is `:ocean`, `:shore` or `:lake`, and it
      is not in a polar row (0, 1, 38, 39). Rivers, nodes and volcanoes are land;
    * every land tile has a **non-zero** ID, every other tile has ID `0`;
    * land tiles are in the same landmass when they touch in any of the **8**
      directions (diagonals count; x wraps around the map, y does not). Two land
      tiles in one landmass share an ID, tiles in different landmasses never do;
    * IDs are **unique across both planes**: no ID is used on Arcanus and
      Myrror. A single-tile island (for example a node) has its own ID.

  The numbering itself looks arbitrary (gaps such as 1, 13, 28, 33, 34), and
  the game never changed the layer in play (not on turn ends, nor on Raise
  Volcano or Change Terrain), so any unused ID is acceptable for a new
  landmass. The polar rows are a *guess* at the boundary: every polar tile on
  every checked map is tundra or coast, so row-based and type-based readings
  agree there.
  """

  alias Mirror.Map, as: MMap
  alias Mirror.TerrainType

  @width 60
  @height 40
  @polar_rows [0, 1, 38, 39]
  @water [:ocean, :shore, :lake]
  @max_id 255
  @planes [:arcanus, :myrror]

  @neighbours for dx <- -1..1, dy <- -1..1, {dx, dy} != {0, 0}, do: {dx, dy}

  @type plane_bins :: %{arcanus: binary(), myrror: binary()}
  @type violation ::
          {:water_has_id, atom(), {integer(), integer()}, integer()}
          | {:land_has_no_id, atom(), {integer(), integer()}}
          | {:landmass_has_mixed_ids, atom(), {integer(), integer()}, [integer()]}
          | {:id_shared, integer(), [{atom(), {integer(), integer()}}]}

  @doc "Is this tile number, on row `y`, land for the landmass layer?"
  @spec land?(integer(), integer()) :: boolean()
  def land?(tile_number, y) do
    y not in @polar_rows and TerrainType.terrain_type(tile_number) not in [nil | @water]
  end

  @doc """
  The landmasses of one plane's terrain: a list of landmasses, each a list of
  `{x, y}` tiles, in scan order of their first tile.
  """
  @spec components(binary()) :: [[{integer(), integer()}]]
  def components(terrain) when is_binary(terrain) do
    land =
      for y <- 0..(@height - 1),
          x <- 0..(@width - 1),
          land?(MMap.get_tile_u16_le(terrain, x, y), y),
          into: MapSet.new() do
        {x, y}
      end

    scan = for y <- 0..(@height - 1), x <- 0..(@width - 1), do: {x, y}

    {comps, _seen} =
      Enum.reduce(scan, {[], MapSet.new()}, fn tile, {comps, seen} ->
        if MapSet.member?(land, tile) and not MapSet.member?(seen, tile) do
          {comp, seen} = flood(land, [tile], MapSet.put(seen, tile), [])
          {[comp | comps], seen}
        else
          {comps, seen}
        end
      end)

    comps |> Enum.map(&Enum.sort_by(&1, fn {x, y} -> {y, x} end)) |> Enum.reverse()
  end

  defp flood(_land, [], seen, acc), do: {acc, seen}

  defp flood(land, [{x, y} = tile | rest], seen, acc) do
    next =
      for {dx, dy} <- @neighbours,
          ny = y + dy,
          ny in 0..(@height - 1),
          n = {MMap.wrap_x(x + dx), ny},
          MapSet.member?(land, n),
          not MapSet.member?(seen, n),
          do: n

    next = Enum.uniq(next)
    flood(land, next ++ rest, Enum.reduce(next, seen, &MapSet.put(&2, &1)), [tile | acc])
  end

  @doc """
  What is inconsistent between `terrain` and `landmass` (each `%{arcanus:, myrror:}`),
  as a list of violations; `[]` means the layer follows the rule.
  """
  @spec violations(plane_bins(), plane_bins()) :: [violation()]
  def violations(terrain, landmass) do
    per_plane =
      for plane <- @planes do
        comps = components(Map.fetch!(terrain, plane))
        {plane, comps, Map.fetch!(landmass, plane)}
      end

    water_and_polar =
      for {plane, comps, lm} <- per_plane,
          land = comps |> List.flatten() |> MapSet.new(),
          y <- 0..(@height - 1),
          x <- 0..(@width - 1),
          not MapSet.member?(land, {x, y}),
          id = MMap.get_tile_u8(lm, x, y),
          id != 0,
          do: {:water_has_id, plane, {x, y}, id}

    per_component =
      for {plane, comps, lm} <- per_plane,
          comp <- comps,
          ids =
            comp
            |> Enum.map(fn {x, y} -> MMap.get_tile_u8(lm, x, y) end)
            |> Enum.uniq()
            |> Enum.sort(),
          problem <- component_problems(plane, hd(comp), comp, lm, ids),
          do: problem

    claims =
      for {plane, comps, lm} <- per_plane,
          comp <- comps,
          ids = comp |> Enum.map(fn {x, y} -> MMap.get_tile_u8(lm, x, y) end) |> Enum.uniq(),
          id <- ids,
          id != 0,
          do: {id, {plane, hd(comp)}}

    shared =
      claims
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.filter(fn {_id, owners} -> length(owners) > 1 end)
      |> Enum.sort()
      |> Enum.map(fn {id, owners} -> {:id_shared, id, owners} end)

    water_and_polar ++ per_component ++ shared
  end

  defp component_problems(plane, first, comp, lm, ids) do
    zeros =
      for {x, y} <- comp, MMap.get_tile_u8(lm, x, y) == 0, do: {:land_has_no_id, plane, {x, y}}

    nonzero = Enum.reject(ids, &(&1 == 0))

    mixed =
      if length(nonzero) > 1, do: [{:landmass_has_mixed_ids, plane, first, nonzero}], else: []

    zeros ++ mixed
  end

  @doc """
  Recompute the landmass layer after terrain edits, changing as little as
  possible: every landmass keeps the ID most of its tiles already carry; when
  two landmasses were joined, the larger keeps its ID; the smaller side of a
  split gets a fresh ID; a new island gets a fresh ID; water and polar rows
  become 0. IDs stay unique across both planes. A layer that already follows
  the rule comes back unchanged.

  Returns `{:error, :out_of_ids}` if more than 255 landmasses would be needed.
  """
  @spec repair(plane_bins(), plane_bins()) :: {:ok, plane_bins()} | {:error, :out_of_ids}
  def repair(terrain, landmass) do
    comps =
      for plane <- @planes,
          comp <- components(Map.fetch!(terrain, plane)) do
        lm = Map.fetch!(landmass, plane)

        ranked =
          comp
          |> Enum.map(fn {x, y} -> MMap.get_tile_u8(lm, x, y) end)
          |> Enum.reject(&(&1 == 0))
          |> Enum.frequencies()
          |> Enum.sort_by(fn {id, n} -> {-n, id} end)
          |> Enum.map(&elem(&1, 0))

        {plane, comp, ranked}
      end

    # Larger landmasses choose first, so a join keeps the bigger one's ID.
    ordered = Enum.sort_by(Enum.with_index(comps), fn {{_, comp, _}, i} -> {-length(comp), i} end)

    {assigned, unassigned, claimed} =
      Enum.reduce(ordered, {[], [], MapSet.new()}, fn {{plane, comp, ranked}, i},
                                                      {done, todo, claimed} ->
        case Enum.find(ranked, &(not MapSet.member?(claimed, &1))) do
          nil -> {done, [{i, plane, comp} | todo], claimed}
          id -> {[{i, plane, comp, id} | done], todo, MapSet.put(claimed, id)}
        end
      end)

    fresh = for id <- 1..@max_id, not MapSet.member?(claimed, id), do: id
    unassigned = Enum.sort(unassigned)

    if length(fresh) < length(unassigned) do
      {:error, :out_of_ids}
    else
      from_fresh =
        unassigned
        |> Enum.zip(fresh)
        |> Enum.map(fn {{i, plane, comp}, id} -> {i, plane, comp, id} end)

      by_plane =
        Enum.group_by(assigned ++ from_fresh, &elem(&1, 1), fn {_i, _plane, comp, id} ->
          {comp, id}
        end)

      {:ok,
       Map.new(@planes, fn plane ->
         ids =
           by_plane
           |> Map.get(plane, [])
           |> Enum.flat_map(fn {comp, id} -> Enum.map(comp, &{&1, id}) end)
           |> Map.new()

         bin =
           for y <- 0..(@height - 1), x <- 0..(@width - 1), into: <<>> do
             <<Map.get(ids, {x, y}, 0)::unsigned-integer-size(8)>>
           end

         {plane, bin}
       end)}
    end
  end
end
