defmodule Mirror.Engine.MapOpsTest do
  use ExUnit.Case, async: true

  alias Mirror.Engine.{MapOps, Topology}

  defp collect_coords(topo, cx, cy, radius) do
    Process.put(:coords, MapSet.new())

    MapOps.each_coord_in_radius(topo, cx, cy, radius, fn x, y ->
      coords = Process.get(:coords)
      Process.put(:coords, MapSet.put(coords, {x, y}))
      true
    end)

    Process.get(:coords)
  end

  test "each_coord_in_radius/5 includes center and ring on square maps" do
    topo = Topology.new(w: 5, h: 5, wrap_x: false, wrap_y: false)

    coords = collect_coords(topo, 2, 2, 1)

    expected =
      for x <- 1..3, y <- 1..3, into: MapSet.new() do
        {x, y}
      end

    assert coords == expected
  end

  test "each_coord_in_radius/5 clamps to bounds without wrapping" do
    topo = Topology.new(w: 5, h: 5, wrap_x: false, wrap_y: false)
    coords = collect_coords(topo, 0, 0, 1)

    assert coords == MapSet.new([{0, 0}, {1, 0}, {0, 1}, {1, 1}])
  end

  test "each_coord_in_radius/5 wraps on x axis when enabled" do
    topo = Topology.new(w: 5, h: 5, wrap_x: true, wrap_y: false)
    coords = collect_coords(topo, 0, 0, 1)

    assert coords == MapSet.new([{0, 0}, {1, 0}, {4, 0}, {0, 1}, {1, 1}, {4, 1}])
  end

  test "each_coord_in_radius/5 ignores negative radius" do
    topo = Topology.new(w: 5, h: 5, wrap_x: false, wrap_y: false)
    coords = collect_coords(topo, 2, 2, -1)

    assert MapSet.size(coords) == 0
  end

  describe "wrapped radius walks (STORY-040)" do
    test "a radius that laps a small wrapped map visits every tile exactly once" do
      topo = %Topology{w: 3, h: 8, wrap_x: true, wrap_y: true}

      coords =
        MapOps.reduce_coords_in_radius(topo, 1, 4, 5, [], fn x, y, acc -> [{x, y} | acc] end)

      assert length(coords) == 24
      assert length(Enum.uniq(coords)) == 24
    end

    test "on an unwrapped map, radius 1 is the 3 x 3 block" do
      topo = %Topology{w: 10, h: 10, wrap_x: false, wrap_y: false}

      coords =
        MapOps.reduce_coords_in_radius(topo, 5, 5, 1, [], fn x, y, acc -> [{x, y} | acc] end)

      assert Enum.sort(coords) == for(x <- 4..6, y <- 4..6, do: {x, y})
    end

    test "the callback walk stops at the same unique tiles" do
      topo = %Topology{w: 3, h: 8, wrap_x: true, wrap_y: true}
      assert MapSet.size(collect_coords(topo, 1, 4, 5)) == 24
    end
  end
end
