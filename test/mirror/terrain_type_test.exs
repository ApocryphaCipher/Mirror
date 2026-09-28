defmodule Mirror.TerrainTypeTest do
  use ExUnit.Case, async: true
  alias Mirror.TerrainType
  alias Mirror.SaveFile
  alias Mirror.Map, as: MMap
  alias Mirror.Engine.Topology

  @myrror_start 0x2FA
  # Ocean, tolerant of Ocean-or-Shore on every side.
  @tile_ocean_loose 0
  # Ocean, but strictly Ocean-only on every side (a "deep ocean" variant).
  @tile_ocean_strict 601
  # Shore, requiring non-Ocean/Shore specifically to its SouthEast.
  @tile_shore 2
  # Grass with only a :center rule — every other direction is unconstrained.
  @tile_grass_unconstrained 162

  describe "terrain_type/1" do
    test "looks up Arcanus tiles directly" do
      assert TerrainType.terrain_type(@tile_ocean_loose) == :ocean
      assert TerrainType.terrain_type(@tile_ocean_strict) == :ocean
      assert TerrainType.terrain_type(@tile_shore) == :shore
    end

    test "maps Myrror tiles back to their Arcanus equivalent" do
      assert TerrainType.terrain_type(@tile_ocean_loose + @myrror_start) == :ocean
      assert TerrainType.terrain_type(@tile_shore + @myrror_start) == :shore
    end

    test "returns nil for out-of-range or negative tile numbers" do
      assert TerrainType.terrain_type(-1) == nil
      assert TerrainType.terrain_type(99_999) == nil
    end
  end

  describe "matches?/2" do
    test "any_of: a direction's neighbour must be one of the allowed types" do
      assert TerrainType.matches?(@tile_ocean_loose, %{0 => :shore, center: :ocean})
      refute TerrainType.matches?(@tile_ocean_loose, %{0 => :grass, center: :ocean})
    end

    test "the strict-ocean variant rejects a Shore neighbour the loose one accepts" do
      assert TerrainType.matches?(@tile_ocean_loose, %{0 => :shore, center: :ocean})
      refute TerrainType.matches?(@tile_ocean_strict, %{0 => :shore, center: :ocean})
    end

    test "none_of: a direction's neighbour must not be one of the forbidden types" do
      # Tile 2 requires non-Ocean/Shore specifically to its SouthEast (direction 3).
      assert TerrainType.matches?(@tile_shore, %{3 => :grass, center: :shore})
      refute TerrainType.matches?(@tile_shore, %{3 => :ocean, center: :shore})
      refute TerrainType.matches?(@tile_shore, %{3 => :shore, center: :shore})
    end

    test "a direction with no rule at all is unconstrained" do
      assert TerrainType.matches?(@tile_grass_unconstrained, %{
               0 => :ocean,
               4 => :volcano,
               center: :grass
             })
    end

    test "works the same for the Myrror-offset tile number" do
      assert TerrainType.matches?(@tile_shore + @myrror_start, %{3 => :grass, center: :shore})
      refute TerrainType.matches?(@tile_shore + @myrror_start, %{3 => :ocean, center: :shore})
    end
  end

  describe "resolve_tile/2" do
    test "returns the first matching tile in ascending index order" do
      # Both 0 and 601 satisfy an all-ocean region; 0 comes first.
      region = for dir <- 0..7, into: %{center: :ocean}, do: {dir, :ocean}
      assert TerrainType.resolve_tile(region, :arcanus) == @tile_ocean_loose
    end

    test "offsets the result by the Myrror start index on the Myrror plane" do
      region = for dir <- 0..7, into: %{center: :ocean}, do: {dir, :ocean}
      assert TerrainType.resolve_tile(region, :myrror) == @tile_ocean_loose + @myrror_start
    end

    test "returns nil when no tile satisfies the region" do
      # No Ocean tile allows Grass as a direct neighbour.
      assert TerrainType.resolve_tile(%{0 => :grass, center: :ocean}, :arcanus) == nil
    end

    test "raises when :center is missing, instead of silently returning nil" do
      assert_raise ArgumentError, ~r/requires :center/, fn ->
        TerrainType.resolve_tile(%{0 => :ocean}, :arcanus)
      end
    end
  end

  @mom_path System.get_env("MIRROR_MOM_PATH")
  @save1_path @mom_path && Path.join(@mom_path, "SAVE1.GAM")
  @has_save1 @save1_path && File.exists?(@save1_path)

  @tag skip: !@has_save1 && "needs SAVE1.GAM"
  test "validates terrain resolution against real save" do
    {:ok, save} = SaveFile.load(@save1_path)

    # 60x40 map
    w = 60
    h = 40

    # To accumulate our results without mutation in a loop
    results =
      for plane <- [:arcanus, :myrror], y <- 0..(h - 1), x <- 0..(w - 1) do
        terrain_bin = save.planes[plane].terrain
        stored_tile = MMap.get_tile_u16_le(terrain_bin, x, y)

        region = build_region(terrain_bin, x, y)

        resolved_tile = TerrainType.resolve_tile(region, plane)

        if resolved_tile == stored_tile do
          {:match, plane, x, y, stored_tile}
        else
          # Is the stored tile at least a valid decorative variant?
          # e.g. 0 vs 601 where 601 is valid for the region but resolved_tile is 0
          variant? = TerrainType.matches?(stored_tile, region)
          {:mismatch, plane, x, y, stored_tile, resolved_tile, region, variant?}
        end
      end

    match_count = Enum.count(results, fn tuple -> elem(tuple, 0) == :match end)
    mismatch_results = Enum.filter(results, fn tuple -> elem(tuple, 0) == :mismatch end)

    variant_count =
      Enum.count(mismatch_results, fn {:mismatch, _, _, _, _, _, _, variant?} -> variant? end)

    unexplained_count = length(mismatch_results) - variant_count

    total = length(results)
    match_rate = match_count / total * 100.0

    IO.puts("""

    --- Terrain Type Validation ---
    Total Tiles: #{total}
    Exact Matches: #{match_count} (#{:erlang.float_to_binary(match_rate, decimals: 2)}%)
    Mismatches: #{length(mismatch_results)}
      - Explained as valid variant (matches rules, just not first): #{variant_count}
      - Unexplained: #{unexplained_count}
    -------------------------------
    """)

    if unexplained_count > 0 do
      # Print some examples
      IO.puts("Sample unexplained mismatches:")

      mismatch_results
      |> Enum.reject(fn {:mismatch, _, _, _, _, _, _, variant?} -> variant? end)
      |> Enum.take(10)
      |> Enum.each(fn {:mismatch, plane, x, y, stored, resolved, region, _} ->
        IO.puts("  #{plane} (#{x}, #{y}) - Stored: #{stored}, Resolved: #{inspect(resolved)}")
        IO.puts("    Region: #{inspect(region)}")
      end)
    end

    assert (match_count + variant_count) / total >= 0.92
  end

  defp build_region(terrain_bin, x, y) do
    center_raw = MMap.get_tile_u16_le(terrain_bin, x, y)
    center_type = TerrainType.terrain_type(center_raw)

    # Start region with center
    region = %{center: center_type || :unknown}

    # 0..7 directions based on Topology.dir_delta
    Enum.reduce(0..7, region, fn dir, acc ->
      {dx, dy} = Topology.dir_delta(dir)

      nx = MMap.wrap_x(x + dx)
      ny = MMap.clamp_y(y + dy)

      neighbor_type =
        case ny do
          :off ->
            # Kazzmir off-map default
            :ocean

          _ ->
            neighbor_raw = MMap.get_tile_u16_le(terrain_bin, nx, ny)
            TerrainType.terrain_type(neighbor_raw) || :unknown
        end

      Map.put(acc, dir, neighbor_type)
    end)
  end
end
