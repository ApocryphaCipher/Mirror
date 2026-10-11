defmodule Mirror.SaveFile.UnitMovementTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.UnitMovement

  test "lizardmen swim (they can also be on land), boats sail, griffins fly" do
    # types from the unit table: 120 Lizardmen Spearmen, 35 Trireme, 136 Griffin
    assert UnitMovement.can_be_on_water?(120)
    assert UnitMovement.swims?(120)
    refute UnitMovement.flies?(120)
    assert UnitMovement.sails?(35)
    assert UnitMovement.flies?(136)
  end

  test "an ordinary land unit cannot, until an enchantment lets it" do
    # type 39: Barbarian Spearmen
    refute UnitMovement.can_be_on_water?(39)
    refute UnitMovement.can_be_on_water?(39, 0x1)
    assert UnitMovement.can_be_on_water?(39, 0x100)
    assert UnitMovement.can_be_on_water?(39, 0x20000)
    assert UnitMovement.can_be_on_water?(39, 0x10000)
  end

  test "spirits and phantoms are non-corporeal" do
    for type <- [154, 170, 176, 191, 192] do
      assert UnitMovement.non_corporeal?(type)
      assert UnitMovement.can_be_on_water?(type)
    end
  end

  test "the water-capable list has no duplicates and leaves out land units" do
    types = UnitMovement.water_capable_types()
    assert types == Enum.uniq(types)
    assert 17 in types and 190 in types
    refute 39 in types
  end
end
