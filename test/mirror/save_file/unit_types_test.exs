defmodule Mirror.SaveFile.UnitTypesTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.UnitTypes

  test "every id from 0 to 197 has a name and a race" do
    assert UnitTypes.count() == 198
    for type <- 0..197, do: assert(UnitTypes.name(type) != "" and UnitTypes.race(type) != nil)
  end

  test "names the game's own units: heroes, boats, races, fantastic" do
    # checked on Kevin's screen: Sky Drake 196, Lizardman spearmen and swordsmen 120/121
    assert UnitTypes.display_name(196) == "Sky Drake"
    assert UnitTypes.display_name(120) == "Lizardman Spearmen"
    assert UnitTypes.display_name(121) == "Lizardman Swordsmen"
    assert UnitTypes.display_name(35) == "Trireme"
    assert UnitTypes.display_name(39) == "Barbarian Spearmen"
    assert UnitTypes.race(0) == :hero
    assert UnitTypes.race(154) == :fantastic
  end

  test "kazzmir's plain typos are corrected" do
    assert UnitTypes.display_name(141) == "Orc Cavalry"
    refute Enum.any?(0..197, &(UnitTypes.name(&1) in ["Calvary", "ElvenLord", "WereWolves"]))
  end

  test "an id outside the table is named, not a crash" do
    assert UnitTypes.name(198) == "unit 198"
    assert UnitTypes.display_name(-1) == "unit -1"
    assert UnitTypes.race(300) == nil
  end

  test "the water-capable types are all in the table" do
    for type <- Mirror.SaveFile.UnitMovement.water_capable_types(),
        do: assert(UnitTypes.race(type))
  end
end
