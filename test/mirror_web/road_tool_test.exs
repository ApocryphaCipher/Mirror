defmodule MirrorWeb.RoadToolTest do
  use ExUnit.Case, async: true

  alias MirrorWeb.RoadTool

  describe "cycle_road/2" do
    test "steps none, road, enchanted road, none" do
      assert RoadTool.cycle_road(0x00) == 0x08
      assert RoadTool.cycle_road(0x08) == 0x18
      assert RoadTool.cycle_road(0x18) == 0x00
    end

    test "steps the other way when asked" do
      assert RoadTool.cycle_road(0x00, true) == 0x18
      assert RoadTool.cycle_road(0x18, true) == 0x08
      assert RoadTool.cycle_road(0x08, true) == 0x00
    end

    test "a byte with only the enchanted bit set is still read as enchanted" do
      assert RoadTool.road_state(0x10) == :enchanted
      assert RoadTool.cycle_road(0x10) == 0x00
    end

    test "keeps corruption and unknown bits" do
      assert RoadTool.cycle_road(0x20) == 0x28
      assert RoadTool.cycle_road(0x28) == 0x38
      assert RoadTool.cycle_road(0x38) == 0x20
      assert RoadTool.cycle_road(0x81) == 0x89
    end
  end

  describe "corruption" do
    test "toggles only its own bit" do
      assert RoadTool.toggle_corruption(0x00) == 0x20
      assert RoadTool.toggle_corruption(0x20) == 0x00
      assert RoadTool.toggle_corruption(0x18) == 0x38
      assert RoadTool.toggle_corruption(0x38) == 0x18
    end
  end

  describe "specials" do
    test "the options are the eleven bytes the game uses" do
      values = Enum.map(RoadTool.special_options(), &elem(&1, 1))
      assert values == ~w(1 2 3 4 5 6 7 8 9 64 128)
    end

    test "parse_special accepts those and nothing else" do
      assert RoadTool.parse_special("64") == 64
      assert RoadTool.parse_special("0") == nil
      assert RoadTool.parse_special("10") == nil
      assert RoadTool.parse_special("gold") == nil
      assert RoadTool.parse_special(4) == nil
    end

    test "describe names what a click did" do
      assert RoadTool.describe(:special, 0, 4) == "Gold ore"
      assert RoadTool.describe(:special, 4, 0) == "Special removed"
      assert RoadTool.describe(:road, 0, 0x18) == "Enchanted road"
      assert RoadTool.describe(:road, 0x18, 0) == "Road removed"
      assert RoadTool.describe(:corruption, 0, 0x20) == "Corrupted"
      assert RoadTool.describe(:corruption, 0x20, 0) == "Corruption removed"
    end
  end
end
