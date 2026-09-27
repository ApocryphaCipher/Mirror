defmodule Mirror.SaveFile.UnitsTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.Units

  @count_offset 0x0009E2
  @units_offset 0x00B734
  @pad_size @units_offset - (@count_offset + 2)

  # Synthetic record builder: 32 bytes per unit.
  defp make_unit_record(opts) do
    x = Keyword.get(opts, :x, 10)
    y = Keyword.get(opts, :y, 10)
    plane = Keyword.get(opts, :plane, 0)
    owner = Keyword.get(opts, :owner, 0)
    max_moves = Keyword.get(opts, :max_moves, 2)
    type = Keyword.get(opts, :type, 39)
    draw_priority = Keyword.get(opts, :draw_priority, 2)

    <<x, y, plane, owner, max_moves, type, 0::size(96), draw_priority, 0::size(104)>>
  end

  defp make_save(records) do
    count = length(records)

    <<0::size(@count_offset * 8), count::little-16, 0::size(@pad_size * 8)>> <>
      IO.iodata_to_binary(records)
  end

  describe "unit decoding and dead unit filtering" do
    test "decodes valid unit records" do
      rec0 = make_unit_record(x: 12, y: 15, plane: 0, owner: 1, type: 39, draw_priority: 3)
      rec1 = make_unit_record(x: 20, y: 25, plane: 1, owner: 4, type: 127, draw_priority: 5)
      raw = make_save([rec0, rec1])

      assert {:ok, [u0, u1]} = Units.parse(raw)

      assert u0 == %{
               index: 0,
               x: 12,
               y: 15,
               plane: :arcanus,
               owner: 1,
               type: 39,
               draw_priority: 3
             }

      assert u1 == %{
               index: 1,
               x: 20,
               y: 25,
               plane: :myrror,
               owner: 4,
               type: 127,
               draw_priority: 5
             }
    end

    test "dead units (0xff owner/plane) and out-of-bounds records are excluded" do
      dead_plane = make_unit_record(x: 10, y: 10, plane: 0xFF, owner: 0)
      dead_owner = make_unit_record(x: 10, y: 10, plane: 0, owner: 0xFF)
      dead_both = make_unit_record(x: 10, y: 10, plane: 0xFF, owner: 0xFF)
      invalid_x = make_unit_record(x: 60, y: 10, plane: 0, owner: 0)
      invalid_y = make_unit_record(x: 10, y: 40, plane: 0, owner: 0)
      invalid_type = make_unit_record(x: 10, y: 10, plane: 0, owner: 0, type: 198)
      valid = make_unit_record(x: 10, y: 10, plane: 0, owner: 0, type: 39)

      raw =
        make_save([
          dead_plane,
          dead_owner,
          dead_both,
          invalid_x,
          invalid_y,
          invalid_type,
          valid
        ])

      assert {:ok, [u]} = Units.parse(raw)
      assert u.index == 6
      assert u.x == 10
      assert u.y == 10
      assert u.type == 39
    end
  end

  describe "stack collapsing" do
    test "a two-wizard stack on one tile collapses to one visible unit" do
      # Wizard 0 with draw_priority 2, Wizard 1 with draw_priority 4
      u0 = make_unit_record(x: 15, y: 15, plane: 0, owner: 0, type: 39, draw_priority: 2)
      u1 = make_unit_record(x: 15, y: 15, plane: 0, owner: 1, type: 40, draw_priority: 4)

      raw = make_save([u0, u1])
      assert {:ok, units} = Units.parse(raw)

      collapsed = Units.collapse_stacks(units)
      assert length(collapsed) == 1
      [top] = collapsed
      assert top.owner == 1
      assert top.type == 40
      assert top.draw_priority == 4
    end

    test "top_of_stack/1 breaks draw_priority ties by lowest save index" do
      u0 = %{index: 2, x: 5, y: 5, plane: :arcanus, owner: 0, type: 10, draw_priority: 3}
      u1 = %{index: 7, x: 5, y: 5, plane: :arcanus, owner: 2, type: 20, draw_priority: 3}

      assert Units.top_of_stack([u0, u1]) == u0
      assert Units.top_of_stack([u1, u0]) == u0
    end
  end

  describe "city and tower hiding" do
    test "a unit on a city tile is hidden on that plane, but not on the other plane" do
      u_arcanus = %{index: 0, x: 10, y: 20, plane: :arcanus, owner: 0, type: 39, draw_priority: 2}
      u_myrror = %{index: 1, x: 10, y: 20, plane: :myrror, owner: 0, type: 39, draw_priority: 2}

      city = %{x: 10, y: 20, plane: :arcanus}

      visible = Units.filter_visible([u_arcanus, u_myrror], [city], [])
      assert visible == [u_myrror]
    end

    test "a unit on a tower tile is hidden regardless of plane" do
      u_arcanus = %{index: 0, x: 14, y: 18, plane: :arcanus, owner: 0, type: 39, draw_priority: 2}
      u_myrror = %{index: 1, x: 14, y: 18, plane: :myrror, owner: 1, type: 40, draw_priority: 3}
      u_other = %{index: 2, x: 15, y: 18, plane: :arcanus, owner: 2, type: 41, draw_priority: 1}

      tower = %{x: 14, y: 18}

      visible = Units.filter_visible([u_arcanus, u_myrror, u_other], [], [tower])
      assert visible == [u_other]
    end
  end

  describe "figure_sprite/1 mapping" do
    test "types 0 and 119 map to UNITS1, 120 and 197 map to UNITS2" do
      assert Units.figure_sprite(0) == {:units1, 0}
      assert Units.figure_sprite(119) == {:units1, 119}
      assert Units.figure_sprite(120) == {:units2, 0}
      assert Units.figure_sprite(197) == {:units2, 77}

      # Out of bounds returns nil
      assert Units.figure_sprite(-1) == nil
      assert Units.figure_sprite(198) == nil
    end
  end

  describe "empty or truncated raw binaries" do
    test "an empty or too-short raw binary returns [] without crashing" do
      assert Units.items(<<>>) == []
      assert Units.items(<<1, 2, 3>>) == []
      assert Units.items(nil) == []
    end

    test "parse/1 returns {:error, :no_units_block} on empty or truncated raw binary" do
      assert Units.parse(<<>>) == {:error, :no_units_block}
      assert Units.parse(<<0::size(@count_offset * 8)>>) == {:error, :no_units_block}
    end

    test "a save with count 0 returns {:ok, []} and items/1 returns []" do
      raw_zero = <<0::size(@count_offset * 8), 0::little-16, 0::size(@pad_size * 8)>>
      assert Units.parse(raw_zero) == {:ok, []}
      assert Units.items(raw_zero) == []
    end
  end

  describe "combined items/3" do
    test "filters dead units, hides city/tower garrisons, collapses stacks, and filters by plane" do
      u_open_arcanus_1 =
        make_unit_record(x: 25, y: 30, plane: 0, owner: 0, type: 39, draw_priority: 2)

      u_open_arcanus_2 =
        make_unit_record(x: 25, y: 30, plane: 0, owner: 1, type: 40, draw_priority: 4)

      u_city_arcanus =
        make_unit_record(x: 10, y: 10, plane: 0, owner: 0, type: 39, draw_priority: 1)

      u_tower_arcanus =
        make_unit_record(x: 5, y: 5, plane: 0, owner: 0, type: 39, draw_priority: 1)

      u_open_myrror =
        make_unit_record(x: 25, y: 30, plane: 1, owner: 2, type: 125, draw_priority: 3)

      raw =
        make_save([
          u_open_arcanus_1,
          u_open_arcanus_2,
          u_city_arcanus,
          u_tower_arcanus,
          u_open_myrror
        ])

      cities = [%{x: 10, y: 10, plane: :arcanus}]
      towers = [%{x: 5, y: 5}]

      # Arcanus plane: city and tower units hidden, stack at (25, 30) collapsed to top unit (priority 4)
      arcanus_items = Units.items(raw, :arcanus, cities: cities, towers: towers)
      assert length(arcanus_items) == 1
      [a_top] = arcanus_items
      assert a_top.x == 25 and a_top.y == 30 and a_top.type == 40

      # Myrror plane: has u_open_myrror
      myrror_items = Units.items(raw, :myrror, cities: cities, towers: towers)
      assert length(myrror_items) == 1
      [m_top] = myrror_items
      assert m_top.x == 25 and m_top.y == 30 and m_top.type == 125
    end
  end

  describe "SAVE1.GAM" do
    @mom_path System.get_env("MIRROR_MOM_PATH", "")
    @save Path.join(@mom_path, "SAVE1.GAM")

    @tag skip: !File.exists?(@save) && "needs MIRROR_MOM_PATH/SAVE1.GAM"
    test "has 42 units including Freya's starting units at Norport (38, 21)" do
      raw = File.read!(@save)
      assert {:ok, units} = Units.parse(raw)
      assert length(units) == 42

      # Freya (owner 0) units at (38, 21)
      norport_units = Enum.filter(units, &(&1.x == 38 and &1.y == 21 and &1.plane == :arcanus))
      assert length(norport_units) == 2

      types = Enum.map(norport_units, & &1.type)
      assert 39 in types
      assert 40 in types

      # Collapsing the stack at Norport picks Barbarian Swordsmen (type 40, draw_priority 4)
      top = Units.top_of_stack(norport_units)
      assert top.type == 40
      assert top.draw_priority == 4

      # Because all starting units in SAVE1 are garrisons inside cities,
      # none appear in the open field
      assert Units.items(raw, :arcanus) == []
      assert Units.items(raw, :myrror) == []
    end
  end
end
