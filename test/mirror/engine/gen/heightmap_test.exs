defmodule Mirror.Engine.Gen.HeightmapTest do
  use ExUnit.Case, async: true

  alias Mirror.Engine.Gen.Heightmap

  defp heightmap_bin(values) do
    Enum.reduce(values, <<>>, fn value, acc ->
      <<acc::binary, value::little-unsigned-integer-size(16)>>
    end)
  end

  test "threshold counts respect inclusive comparisons" do
    bin = heightmap_bin([0, 1, 1, 2, 2])

    assert Heightmap.count_tiles_above_threshold(bin, 1) == 4
    assert Heightmap.count_tiles_below_threshold(bin, 1) == 3
  end

  test "find height with specified tile count above and below" do
    bin = heightmap_bin([0, 0, 1, 2, 2, 3])

    assert Heightmap.find_height_with_specified_tile_count_above(bin, 2) == 2
    assert Heightmap.find_height_with_specified_tile_count_above(bin, 1) == 3
    assert Heightmap.find_height_with_specified_tile_count_below(bin, 3) == 1
  end
end
