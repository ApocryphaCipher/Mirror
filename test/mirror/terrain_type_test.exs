defmodule Mirror.TerrainTypeTest do
  use ExUnit.Case, async: true
  alias Mirror.TerrainType
  alias Mirror.SaveFile
  alias Mirror.Map, as: MMap
  alias Mirror.Engine.Topology

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
