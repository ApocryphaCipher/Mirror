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
end
