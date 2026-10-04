defmodule Mirror.LandmassTest do
  use ExUnit.Case, async: true

  alias Mirror.Landmass
  alias Mirror.Map, as: MMap

  @ocean 0
  @grass 162
  @shore 2
  @lake 18
  @river 185
  @node 168

  # Terrain plane: ocean everywhere except the given {x, y} => tile entries.
  defp terrain(land) do
    for y <- 0..39, x <- 0..59, into: <<>> do
      <<Map.get(land, {x, y}, @ocean)::little-unsigned-16>>
    end
  end

  defp lm(ids) do
    for y <- 0..39, x <- 0..59, into: <<>> do
      <<Map.get(ids, {x, y}, 0)::unsigned-8>>
    end
  end

  defp block(x0, y0, w, h, tile \\ @grass),
    do: for(x <- x0..(x0 + w - 1), y <- y0..(y0 + h - 1), into: %{}, do: {{x, y}, tile})

  defp ids_for(tiles, id), do: Map.new(Map.keys(tiles), &{&1, id})

  defp planes(arcanus, myrror), do: %{arcanus: arcanus, myrror: myrror}

  defp tiles_of(landmass_bin, plane_ids) do
    for y <- 0..39, x <- 0..59, MMap.get_tile_u8(landmass_bin, x, y) in plane_ids, do: {x, y}
  end

  describe "land?/2" do
    test "ocean, coast and lake are water; everything else is land" do
      refute Landmass.land?(@ocean, 10)
      refute Landmass.land?(@shore, 10)
      refute Landmass.land?(@lake, 10)
      assert Landmass.land?(@grass, 10)
      assert Landmass.land?(@river, 10)
      assert Landmass.land?(@node, 10)
    end

    test "the polar rows are never land" do
      for y <- [0, 1, 38, 39], do: refute(Landmass.land?(@grass, y))
      for y <- [2, 37], do: assert(Landmass.land?(@grass, y))
    end
  end

  describe "components/1" do
    test "separate islands are separate landmasses" do
      t = terrain(Map.merge(block(5, 5, 3, 3), block(20, 5, 2, 2)))
      assert [a, b] = Landmass.components(t)
      assert length(a) == 9 and length(b) == 4
    end

    test "tiles touching only diagonally are one landmass" do
      t = terrain(%{{5, 5} => @grass, {6, 6} => @grass})
      assert [[_, _]] = Landmass.components(t)
    end

    test "x wraps around the map edge" do
      t = terrain(%{{0, 10} => @grass, {59, 10} => @grass})
      assert [[_, _]] = Landmass.components(t)
    end

    test "y does not wrap" do
      t = terrain(%{{10, 2} => @grass, {10, 37} => @grass})
      assert [_, _] = Landmass.components(t)
    end

    test "a single node tile is its own landmass" do
      t = terrain(%{{30, 20} => @node})
      assert [[{30, 20}]] = Landmass.components(t)
    end
  end

  describe "violations/2" do
    test "a layer that follows the rule has none" do
      a = block(5, 5, 3, 3)
      t = planes(terrain(a), terrain(%{}))
      l = planes(lm(ids_for(a, 7)), lm(%{}))
      assert Landmass.violations(t, l) == []
    end

    test "water carrying an ID" do
      t = planes(terrain(%{}), terrain(%{}))
      l = planes(lm(%{{3, 3} => 4}), lm(%{}))
      assert [{:water_has_id, :arcanus, {3, 3}, 4}] = Landmass.violations(t, l)
    end

    test "land with ID 0" do
      t = planes(terrain(%{{3, 3} => @grass}), terrain(%{}))
      l = planes(lm(%{}), lm(%{}))
      assert [{:land_has_no_id, :arcanus, {3, 3}}] = Landmass.violations(t, l)
    end

    test "one landmass with two IDs" do
      a = block(5, 5, 2, 1)
      t = planes(terrain(a), terrain(%{}))
      l = planes(lm(%{{5, 5} => 3, {6, 5} => 4}), lm(%{}))
      assert [{:landmass_has_mixed_ids, :arcanus, {5, 5}, [3, 4]}] = Landmass.violations(t, l)
    end

    test "one ID on two landmasses, including across planes" do
      a = %{{5, 5} => @grass, {20, 5} => @grass}
      t = planes(terrain(a), terrain(%{{9, 9} => @grass}))
      l = planes(lm(%{{5, 5} => 3, {20, 5} => 3}), lm(%{{9, 9} => 3}))
      assert [{:id_shared, 3, owners}] = Landmass.violations(t, l)
      assert length(owners) == 3
    end
  end

  describe "repair/2" do
    test "leaves a consistent layer exactly as it was" do
      a = Map.merge(block(5, 5, 3, 3), block(20, 5, 2, 2))
      m = block(10, 10, 4, 4)
      t = planes(terrain(a), terrain(m))

      l =
        planes(
          lm(Map.merge(ids_for(block(5, 5, 3, 3), 7), ids_for(block(20, 5, 2, 2), 12))),
          lm(ids_for(m, 30))
        )

      assert Landmass.violations(t, l) == []
      assert {:ok, ^l} = Landmass.repair(t, l)
    end

    test "land turned to water gets ID 0" do
      before = block(5, 5, 3, 3)
      l = planes(lm(ids_for(before, 7)), lm(%{}))
      t = planes(terrain(Map.delete(before, {6, 6})), terrain(%{}))

      assert {:ok, fixed} = Landmass.repair(t, l)
      assert MMap.get_tile_u8(fixed.arcanus, 6, 6) == 0
      assert MMap.get_tile_u8(fixed.arcanus, 5, 5) == 7
      assert Landmass.violations(t, fixed) == []
    end

    test "joining two landmasses: the larger keeps its ID, the smaller takes it" do
      big = block(5, 5, 4, 4)
      small = block(12, 5, 2, 2)
      l = planes(lm(Map.merge(ids_for(big, 7), ids_for(small, 9))), lm(%{}))
      bridge = block(9, 5, 3, 1)

      t =
        planes(terrain(Enum.reduce([big, small, bridge], %{}, &Map.merge(&2, &1))), terrain(%{}))

      assert {:ok, fixed} = Landmass.repair(t, l)
      assert tiles_of(fixed.arcanus, [9]) == []
      assert length(tiles_of(fixed.arcanus, [7])) == 16 + 4 + 3
      assert Landmass.violations(t, fixed) == []
    end

    test "splitting a landmass: the larger part keeps the ID, the other gets a fresh one" do
      whole = Map.merge(block(5, 5, 6, 1), block(5, 6, 6, 1))
      l = planes(lm(ids_for(whole, 7)), lm(%{}))
      # remove columns 8 and 9: a two-tile gap cannot be bridged even diagonally
      cut = Map.drop(whole, for(x <- 8..9, y <- 5..6, do: {x, y}))
      t = planes(terrain(cut), terrain(%{}))

      assert {:ok, fixed} = Landmass.repair(t, l)
      left = tiles_of(fixed.arcanus, [7])
      assert length(left) == 6
      assert Enum.all?(left, fn {x, _} -> x <= 7 end)

      [other] =
        Enum.uniq(for {x, y} <- Map.keys(cut), x >= 10, do: MMap.get_tile_u8(fixed.arcanus, x, y))

      assert other not in [0, 7]
      assert Landmass.violations(t, fixed) == []
    end

    test "a new island gets an ID unused on either plane" do
      other_plane = block(10, 10, 2, 2)
      a = block(5, 5, 2, 2)
      l = planes(lm(ids_for(a, 1)), lm(ids_for(other_plane, 2)))
      t = planes(terrain(Map.put(a, {30, 30}, @grass)), terrain(other_plane))

      assert {:ok, fixed} = Landmass.repair(t, l)
      new_id = MMap.get_tile_u8(fixed.arcanus, 30, 30)
      assert new_id not in [0, 1, 2]
      assert Landmass.violations(t, fixed) == []
    end

    test "land painted into a polar row gets ID 0" do
      t = planes(terrain(%{{10, 1} => @grass, {10, 2} => @grass}), terrain(%{}))
      l = planes(lm(%{{10, 1} => 5, {10, 2} => 5}), lm(%{}))

      assert {:ok, fixed} = Landmass.repair(t, l)
      assert MMap.get_tile_u8(fixed.arcanus, 10, 1) == 0
      assert MMap.get_tile_u8(fixed.arcanus, 10, 2) == 5
    end

    test "runs out of IDs only past 255 landmasses" do
      many = for x <- 0..58//2, y <- 2..37//2, into: %{}, do: {{x, y}, @grass}
      assert map_size(many) > 255
      t = planes(terrain(many), terrain(%{}))
      assert {:error, :out_of_ids} = Landmass.repair(t, planes(lm(%{}), lm(%{})))
    end
  end

  @mom_path System.get_env("MIRROR_MOM_PATH")
  @save1 @mom_path && Path.join(@mom_path, "SAVE1.GAM")

  describe "real saves" do
    @tag skip: !(@save1 && File.exists?(@save1)) && "needs SAVE1.GAM (set MIRROR_SAVE1)"
    test "a real generated map follows the rule, and repair leaves it unchanged" do
      {:ok, save} = Mirror.SaveFile.load(@save1)
      t = %{arcanus: save.planes.arcanus.terrain, myrror: save.planes.myrror.terrain}
      l = %{arcanus: save.planes.arcanus.landmass, myrror: save.planes.myrror.landmass}

      assert Landmass.violations(t, l) == []
      assert {:ok, ^l} = Landmass.repair(t, l)
    end
  end
end
