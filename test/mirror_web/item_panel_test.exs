defmodule MirrorWeb.ItemPanelTest do
  use ExUnit.Case, async: true

  alias MirrorWeb.ItemPanel

  @item %{
    index: 4,
    name: "Staff of Zap",
    type_name: "Staff",
    slot_name: "staff or wand",
    cost: 900,
    attack: 0,
    to_hit: 1,
    defense: 3,
    movement: 0,
    resistance: 0,
    spell_skill: 5,
    spell_save: 2,
    spell: 67,
    charges: 4,
    abilities: 0x4000 + 0x40
  }

  @powers [
    %{index: 0, name: "+3 Defense", kind: 2, realm: 0, amount: 3, mask: 0},
    %{index: 1, name: "Haste", kind: 9, realm: 1, amount: 7, mask: 0x4000},
    %{index: 2, name: "Regeneration", kind: 9, realm: 0, amount: 6, mask: 0x40}
  ]

  test "describes the item in words: kind, stats, powers and the charged spell" do
    table = %{67 => %{number: 67, name: "Mind Storm", realm: :sorcery, cost: 0, research: 0}}

    assert %{
             index: 4,
             name: "Staff of Zap",
             kind: "Staff",
             cost: 900,
             stats: ["+1 To Hit", "+3 Defense", "+5 Spell Skill", "-2 Spell Save"],
             powers: ["Haste", "Regeneration"],
             unnamed_powers: false,
             spell: "Mind Storm ×4"
           } = ItemPanel.describe(@item, @powers, table)
  end

  test "without the game files the stats show and the powers are flagged, not guessed" do
    d = ItemPanel.describe(@item, nil, nil)
    assert d.powers == []
    assert d.unnamed_powers
    assert d.spell == "Spell 67 ×4"
    assert "+3 Defense" in d.stats

    plain = ItemPanel.describe(%{@item | abilities: 0, spell: 0}, nil, nil)
    refute plain.unnamed_powers
    assert plain.spell == nil
  end

  test "movement is stored in half points: 8 shows as +4, 3 as +1.5" do
    assert "+4 Movement" in ItemPanel.describe(%{@item | movement: 8}, [], nil).stats
    assert "+1.5 Movement" in ItemPanel.describe(%{@item | movement: 3}, [], nil).stats

    refute Enum.any?(
             ItemPanel.describe(%{@item | movement: 0}, [], nil).stats,
             &(&1 =~ "Movement")
           )
  end

  test "an item with an unknown type is still called an item" do
    assert ItemPanel.describe(%{@item | type_name: nil, slot_name: nil}, [], nil).kind == "item"

    assert ItemPanel.describe(%{@item | type_name: nil, slot_name: "misc"}, [], nil).kind ==
             "misc"
  end
end
