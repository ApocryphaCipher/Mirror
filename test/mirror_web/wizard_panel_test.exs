defmodule MirrorWeb.WizardPanelTest do
  use ExUnit.Case, async: true

  alias MirrorWeb.WizardPanel
  alias Mirror.WizardFixture

  test "reads the fields of wizard 1 as the page shows them" do
    d = WizardPanel.details(WizardFixture.synthetic(), 1)

    assert d.name == "Jafar"
    assert d.id == 1 and d.record == 0
    assert d.banner == :blue
    assert {d.fame, d.power_base, d.gold, d.mana} == {10, 12, 1234, 500}
    assert d.casting_skill == 60
    assert d.tax == "1 gold per citizen"
    assert d.circle == %{x: 38, y: 21, plane: :myrror}
    assert d.ratios == %{research: 34, mana: 33, skill: 33}
    assert d.books == [{"Sorcery", 12}, {"Life", 3}]
    assert d.retorts == ["Alchemy", "Famous"]
    assert d.researching == %{number: 19, realm: "Nature"}
    assert d.research_left == 383

    assert d.spells == [
             {"Nature", 1},
             {"Sorcery", 1},
             {"Chaos", 0},
             {"Life", 0},
             {"Death", 0},
             {"Arcane", 0}
           ]

    assert d.standing == %{cities: 0, units: 0, nodes: 0}
  end

  test "a rival is wizard 2; its banner picks the colour" do
    d = WizardPanel.details(WizardFixture.synthetic(), 2)
    assert d.name == "Sharee"
    assert d.banner == :red
    assert d.colour == WizardPanel.colour(:red)
  end

  test "no such wizard: nameless record, neutral player, out of range, wrong type" do
    raw = WizardFixture.synthetic()
    assert WizardPanel.details(raw, 3) == nil
    assert WizardPanel.details(raw, 6) == nil
    assert WizardPanel.details(raw, 0) == nil
    assert WizardPanel.details(raw, 99) == nil
    assert WizardPanel.details(raw, "1") == nil
    assert WizardPanel.details(<<1, 2, 3>>, 1) == nil
  end

  test "wizards/1 lists the named wizards by page number; page_id maps owners" do
    assert WizardPanel.wizards(WizardFixture.synthetic()) == [{1, "Jafar"}, {2, "Sharee"}]
    assert WizardPanel.wizards(nil) == []
    assert WizardPanel.page_id(0, "Jafar") == 1
    assert WizardPanel.page_id(4, "Kali") == 5
    assert WizardPanel.page_id(5, "Neutral") == nil
    assert WizardPanel.page_id(nil, "Neutral") == nil
    # a record with no name has no page, so its label stays text
    assert WizardPanel.page_id(2, "") == nil
  end

  describe "changes/2 (the edit form)" do
    setup do
      %{d: WizardPanel.details(WizardFixture.synthetic(), 1)}
    end

    test "keeps only what differs", %{d: d} do
      params = %{
        "name" => "Jafar",
        "gold" => "1234",
        "mana" => "900",
        "fame" => "10",
        "books" => %{"0" => "0", "1" => "12", "2" => "0", "3" => "3", "4" => "0"},
        "retorts_present" => "1",
        "retorts" => %{"0" => "on", "13" => "on"}
      }

      assert WizardPanel.changes(params, d) == {:ok, [mana: 900]}
    end

    test "name, books and retorts become changes; unticked boxes are false", %{d: d} do
      params = %{
        "name" => "  Merlin ",
        "books" => %{"0" => "5", "1" => "12", "2" => "0", "3" => "3", "4" => "0"},
        "retorts_present" => "1",
        "retorts" => %{"13" => "on", "17" => "on"}
      }

      assert {:ok, [name: "Merlin", books: [5, 12, 0, 3, 0], retorts: retorts]} =
               WizardPanel.changes(params, d)

      assert Enum.with_index(retorts) |> Enum.filter(&elem(&1, 0)) |> Enum.map(&elem(&1, 1)) == [
               13,
               17
             ]
    end

    test "a form without the retort box sends no retort change", %{d: d} do
      assert WizardPanel.changes(%{"gold" => "5"}, d) == {:ok, [gold: 5]}
    end

    test "a value that is not a number names its field", %{d: d} do
      assert WizardPanel.changes(%{"gold" => "lots"}, d) == {:error, :bad_gold}
      assert WizardPanel.changes(%{"fame" => "1.5"}, d) == {:error, :bad_fame}
      assert WizardPanel.changes(%{"books" => %{"0" => "x"}}, d) == {:error, :bad_books}
    end

    test "client-controlled values of the wrong type are refused, not raised", %{d: d} do
      assert WizardPanel.changes(%{"name" => nil}, d) == {:error, :bad_name}
      assert WizardPanel.changes(%{"name" => 5}, d) == {:error, :bad_name}
      assert WizardPanel.changes(%{"books" => nil}, d) == {:error, :bad_books}
      assert WizardPanel.changes(%{"books" => "x"}, d) == {:error, :bad_books}

      assert WizardPanel.changes(%{"retorts_present" => "1", "retorts" => nil}, d) ==
               {:error, :bad_retorts}

      assert WizardPanel.changes(%{"retorts_present" => "1", "retorts" => "on"}, d) ==
               {:error, :bad_retorts}
    end

    test "label and error words", %{d: d} do
      assert WizardPanel.label(d, gold: 5, books: [1, 1, 1, 1, 1]) ==
               "Edited Jafar: gold 5, books"

      assert WizardPanel.error_message(:bad_gold) =~ "0 to 30000"
    end
  end

  describe "spells and research" do
    setup do
      %{d: WizardPanel.details(WizardFixture.synthetic(), 1)}
    end

    # the fixture: spell 1 known, 2 and 3 knowable, 41 known; researching 19, 383 left
    test "details carry the library and the researched spell number", %{d: d} do
      assert Enum.take(d.library, 3) == [2, 1, 1]
      assert length(d.library) == 214
      assert d.researching_number == 19
    end

    test "ticked spells become known; unticking a known one makes it knowable", %{d: d} do
      params = %{"spells_present" => "1", "spells" => %{"2" => "on", "3" => "on", "41" => "on"}}
      # 1 was known and is not ticked: knowable again (1); 2 and 3 become known; 41 stays known
      assert WizardPanel.changes(params, d) == {:ok, [spells: [{1, 1}, {2, 2}, {3, 2}]]}
    end

    test "without spells_present the spell boxes are not read", %{d: d} do
      assert WizardPanel.changes(%{"spells" => %{"3" => "on"}}, d) == {:ok, []}
    end

    test "a spell on the research list stays on it when not ticked", %{d: d} do
      d = %{d | library: List.replace_at(d.library, 4, 3)}
      params = %{"spells_present" => "1", "spells" => %{"1" => "on", "41" => "on"}}
      assert WizardPanel.changes(params, d) == {:ok, []}
    end

    test "researching and points left are changes only when they differ", %{d: d} do
      assert WizardPanel.changes(%{"researching" => "19", "research_left" => "383"}, d) ==
               {:ok, []}

      assert WizardPanel.changes(%{"researching" => "3", "research_left" => "0"}, d) ==
               {:ok, [researching: 3, research_left: 0]}

      # 98 is not one of the game's candidates (19, 3, 53): its Research page could not show it
      assert WizardPanel.changes(%{"researching" => "98"}, d) == {:error, :not_offered}
      assert WizardPanel.changes(%{"researching" => "0"}, d) == {:error, :not_offered}

      assert WizardPanel.changes(%{"researching" => "x"}, d) == {:error, :bad_researching}
      assert WizardPanel.changes(%{"research_left" => "-"}, d) == {:error, :bad_research_left}
    end

    test "the research picker offers the game's candidates and the spell being researched", %{
      d: d
    } do
      assert d.candidates == [19, 3, 53]
      assert WizardPanel.research_options(d) == [19, 3, 53]
      assert WizardPanel.research_options(%{d | researching_number: 98}) == [19, 3, 53, 98]
      assert WizardPanel.research_options(%{d | researching_number: 0}) == [19, 3, 53]
      assert WizardPanel.error_message(:not_offered) =~ "research list"
    end

    test "a spells value that is not a map is refused", %{d: d} do
      assert WizardPanel.changes(%{"spells_present" => "1", "spells" => nil}, d) ==
               {:error, :bad_spells}
    end

    test "learn_realm lists the realm's spells that are not yet known", %{d: d} do
      assert {:ok, changes} = {:ok, WizardPanel.learn_realm(d, :nature)}
      assert [spells: list] = changes
      assert length(list) == 39
      assert {1, 2} not in list
      assert Enum.all?(list, fn {n, s} -> n in 1..40 and s == 2 end)

      # sorcery has spell 41 known already
      assert [spells: sorcery] = WizardPanel.learn_realm(d, :sorcery)
      assert length(sorcery) == 39

      assert [spells: arcane] = WizardPanel.learn_realm(d, :arcane)
      assert Enum.map(arcane, &elem(&1, 0)) == Enum.to_list(201..214)

      assert WizardPanel.learn_realm(d, :nonsense) == []
      all_known = %{d | library: List.duplicate(2, 214)}
      assert WizardPanel.learn_realm(all_known, :death) == []
    end

    test "spell_rows groups by realm with names from the table or numbers without one", %{d: d} do
      rows = WizardPanel.spell_rows(d, nil)
      assert Enum.map(rows, &elem(&1, 0)) == [:nature, :sorcery, :chaos, :life, :death, :arcane]
      assert rows |> Enum.map(fn {_, r} -> length(r) end) == [40, 40, 40, 40, 40, 14]
      {:nature, [first | _]} = hd(rows)
      assert %{number: 1, name: "Spell 1", state: 2, cost: nil} = first

      table = %{1 => %{name: "Earth to Mud", cost: 15}}
      {:nature, [first | _]} = hd(WizardPanel.spell_rows(d, table))
      assert %{name: "Earth to Mud", cost: 15} = first
    end

    test "labels and error words for the new fields" do
      d = %{name: "Jafar"}
      assert WizardPanel.label(d, spells: [{1, 2}]) == "Edited Jafar: 1 spell"

      assert WizardPanel.label(d, spells: [{1, 2}, {2, 2}], researching: 0) =~
               "2 spells, no spell researched"

      assert WizardPanel.label(d, research_left: 5) == "Edited Jafar: 5 research points left"
      assert WizardPanel.error_message(:bad_researching) =~ "1 to 214"
    end
  end

  describe "relations and global enchantments" do
    test "the relations list is every other named wizard plus the neutral player" do
      d = WizardPanel.details(WizardFixture.synthetic(), 1)
      assert Enum.map(d.relations, & &1.other) == [1, 5]

      assert %{
               name: "Sharee",
               page: 2,
               contacted: true,
               relation: 25,
               status: 1,
               tag: "Wizard pact"
             } =
               Enum.at(d.relations, 0)

      assert %{name: "Neutral", page: nil, contacted: false, relation: -81, status: 3, tag: "War"} =
               Enum.at(d.relations, 1)
    end

    test "a rival's list has the player and the neutral player, with a negative relation" do
      d = WizardPanel.details(WizardFixture.synthetic(), 2)
      assert Enum.map(d.relations, & &1.other) == [0, 5]

      assert %{name: "Jafar", page: 1, relation: -20, contacted: true, tag: "None"} =
               hd(d.relations)
    end

    test "statuses 0 to 3 are confirmed in the game (2026-10-13); 4 is not" do
      for s <- 0..3, do: assert(WizardPanel.status_checked?(s))
      refute WizardPanel.status_checked?(4)

      assert WizardPanel.status_options(1) |> Enum.map(&elem(&1, 1)) == [
               "None",
               "Wizard pact",
               "Alliance",
               "War"
             ]

      assert List.last(WizardPanel.status_options(4)) == {4, "Final war?"}
    end

    test "the edit form's relation rows become one change, only for what differs" do
      d = WizardPanel.details(WizardFixture.synthetic(), 1)
      # fixture: Sharee (other 1) relation 25, status 1; neutral (5) -81, status 3

      same = %{
        "relations_present" => "1",
        "relations" => %{"1" => %{"relation" => "25", "status" => "1"}}
      }

      assert WizardPanel.changes(same, d) == {:ok, []}

      both = %{
        "relations_present" => "1",
        "relations" => %{"1" => %{"relation" => "-40", "status" => "3"}}
      }

      assert WizardPanel.changes(both, d) == {:ok, [relations: [{1, -40, 3}]]}

      only_status = %{
        "relations_present" => "1",
        "relations" => %{"1" => %{"relation" => "25", "status" => "2"}}
      }

      assert WizardPanel.changes(only_status, d) == {:ok, [relations: [{1, nil, 2}]]}

      # the neutral player's row is not editable: ignored
      neutral = %{
        "relations_present" => "1",
        "relations" => %{"5" => %{"relation" => "0", "status" => "0"}}
      }

      assert WizardPanel.changes(neutral, d) == {:ok, []}

      # without relations_present the rows are not read
      assert WizardPanel.changes(%{"relations" => %{"1" => %{"relation" => "9"}}}, d) == {:ok, []}
    end

    test "bad relation values are refused" do
      d = WizardPanel.details(WizardFixture.synthetic(), 1)
      bad = &%{"relations_present" => "1", "relations" => &1}

      assert WizardPanel.changes(bad.(%{"1" => %{"relation" => "x"}}), d) ==
               {:error, :bad_relations}

      assert WizardPanel.changes(bad.(%{"1" => %{"status" => "1.5"}}), d) ==
               {:error, :bad_relations}

      assert WizardPanel.changes(bad.(%{"1" => "nope"}), d) == {:error, :bad_relations}
      assert WizardPanel.changes(bad.(nil), d) == {:error, :bad_relations}
      # in range here: Structures refuses 101 and the page says so
      assert {:ok, [relations: [{1, 101, nil}]]} =
               WizardPanel.changes(bad.(%{"1" => %{"relation" => "101"}}), d)
    end

    test "the label names the wizards" do
      d = WizardPanel.details(WizardFixture.synthetic(), 1)

      assert WizardPanel.label(d, relations: [{1, 5, nil}]) ==
               "Edited Jafar: relations with Sharee"

      assert WizardPanel.error_message(:bad_relations) =~ "-100 to 100"
    end

    test "active globals are the bytes that are not zero, by name, in the save's order" do
      d = WizardPanel.details(WizardFixture.synthetic(), 1)
      assert d.globals == ["Aura of Majesty", "Just Cause"]
      assert WizardPanel.details(WizardFixture.synthetic(), 2).globals == []
      assert length(WizardPanel.global_names()) == 24
      assert Enum.at(WizardPanel.global_names(), 3) == "Aura of Majesty"
      assert Enum.at(WizardPanel.global_names(), 18) == "Just Cause"
    end
  end

  describe "banished wizards" do
    test "a wizard whose fortress is inactive is banished, and so is his row on the others' pages" do
      raw = WizardFixture.synthetic()
      refute WizardPanel.details(raw, 1).banished
      refute WizardPanel.details(raw, 2).banished

      dead = WizardFixture.banish(raw, 1)
      assert WizardPanel.details(dead, 2).banished
      refute WizardPanel.details(dead, 1).banished

      assert %{banished: true} =
               Enum.find(WizardPanel.details(dead, 1).relations, &(&1.other == 1))

      assert %{banished: false} =
               Enum.find(WizardPanel.details(dead, 1).relations, &(&1.other == 5))
    end

    test "a banished wizard's relation row is not editable" do
      dead = WizardFixture.banish(WizardFixture.synthetic(), 1)
      d = WizardPanel.details(dead, 1)

      params = %{
        "relations_present" => "1",
        "relations" => %{"1" => %{"relation" => "-40", "status" => "3"}}
      }

      assert WizardPanel.changes(params, d) == {:ok, []}
    end

    test "a save with no fortress block is not read as banished" do
      raw = WizardFixture.synthetic()
      refute WizardPanel.details(binary_part(raw, 0, 0x9E8 + 6 * 0x4C8), 1).banished
    end
  end

  describe "global enchantment checkboxes" do
    setup do
      %{d: WizardPanel.details(WizardFixture.synthetic(), 1)}
    end

    test "flags list all 24 in the save's order", %{d: d} do
      assert length(d.global_flags) == 24
      assert Enum.at(d.global_flags, 3) == {"Aura of Majesty", true}
      assert Enum.at(d.global_flags, 7) == {"Nature Awareness", false}
    end

    test "unchanged boxes make no change", %{d: d} do
      params = %{"globals_present" => "1", "globals" => %{"3" => "on", "18" => "on"}}
      assert WizardPanel.changes(params, d) == {:ok, []}
    end

    test "ticking and unticking becomes one :globals change", %{d: d} do
      params = %{"globals_present" => "1", "globals" => %{"3" => "on", "7" => "on"}}
      assert {:ok, [globals: wanted]} = WizardPanel.changes(params, d)
      assert for({true, i} <- Enum.with_index(wanted), do: i) == [3, 7]
      assert WizardPanel.label(d, globals: wanted) == "Edited Jafar: global enchantments"
    end

    test "Time Stop keeps the save's value whatever the form says", %{d: d} do
      params = %{"globals_present" => "1", "globals" => %{"3" => "on", "6" => "on", "18" => "on"}}
      assert WizardPanel.changes(params, d) == {:ok, []}
    end

    test "a globals value that is not a map is refused", %{d: d} do
      assert WizardPanel.changes(%{"globals_present" => "1", "globals" => "on"}, d) ==
               {:error, :bad_globals}
    end
  end

  describe "hero edit form" do
    setup do
      %{d: WizardPanel.details(WizardFixture.with_hero(WizardFixture.synthetic()), 1)}
    end

    test "details carry the hero with its damage", %{d: d} do
      assert [%{slot: 0, name: "Harold", level: 2, experience: 27, damage: 3}] = d.heroes
    end

    test "keeps only what differs", %{d: d} do
      same = %{"name" => "Harold", "level" => "2", "experience" => "27", "damage" => "3"}
      assert WizardPanel.hero_changes(same, d, 0) == {:ok, []}

      assert WizardPanel.hero_changes(%{same | "name" => "Sir H", "damage" => "0"}, d, 0) ==
               {:ok, [name: "Sir H", damage: 0]}
    end

    test "refuses what is not a number, and a slot with no hero", %{d: d} do
      assert WizardPanel.hero_changes(%{"level" => "abc"}, d, 0) == {:error, :bad_level}
      assert WizardPanel.hero_changes(%{"name" => "x"}, d, 3) == {:error, :no_such_hero}
      assert WizardPanel.error_message(:bad_hero_name) =~ "1 to 13"
    end

    test "the label names the hero and the fields", %{d: d} do
      [hero] = d.heroes

      assert WizardPanel.hero_label(hero, name: "Sir H", level: 3) ==
               "Edited hero Harold: name Sir H, level 3"
    end
  end

  describe "item edit form" do
    @item %{
      index: 4,
      name: "Staff of Zap",
      cost: 900,
      attack: 0,
      to_hit: 1,
      defense: 3,
      movement: 4,
      resistance: 0,
      spell_skill: 5,
      spell_save: 0,
      abilities: 0x4000 + 0x80_0000_00
    }
    @powers [
      %{index: 0, name: "+3 Defense", kind: 2, realm: 0, amount: 3, mask: 0},
      %{index: 1, name: "Haste", kind: 9, realm: 1, amount: 7, mask: 0x4000},
      %{index: 2, name: "Regeneration", kind: 9, realm: 0, amount: 6, mask: 0x40}
    ]

    @same %{
      "name" => "Staff of Zap",
      "cost" => "900",
      "attack" => "0",
      "to_hit" => "1",
      "defense" => "3",
      "movement" => "2",
      "resistance" => "0",
      "spell_skill" => "5",
      "spell_save" => "0"
    }

    test "keeps only what differs; movement is typed as the screen shows it" do
      assert WizardPanel.item_changes(@same, @item, @powers) == {:ok, []}

      assert WizardPanel.item_changes(
               %{
                 @same
                 | "name" => " Rod ",
                   "cost" => "10",
                   "movement" => "3.5",
                   "defense" => "6"
               },
               @item,
               @powers
             ) == {:ok, [name: "Rod", cost: 10, defense: 6, movement: 7]}
    end

    test "powers are ticked boxes; bits no power owns are kept" do
      ticked = fn masks ->
        Map.merge(@same, %{
          "powers_present" => "1",
          "powers" => Map.new(masks, &{Integer.to_string(&1), "on"})
        })
      end

      # Haste stays, Regeneration is added, the unowned bit 0x8000000 stays
      assert WizardPanel.item_changes(ticked.([0x4000, 0x40]), @item, @powers) ==
               {:ok, [abilities: 0x4000 + 0x40 + 0x80_0000_00]}

      # nothing ticked removes Haste only
      assert WizardPanel.item_changes(ticked.([]), @item, @powers) ==
               {:ok, [abilities: 0x80_0000_00]}

      assert WizardPanel.item_changes(ticked.([0x4000]), @item, @powers) == {:ok, []}

      # without the power table the boxes are not offered, so the powers are left alone
      assert WizardPanel.item_changes(ticked.([]), @item, nil) == {:ok, []}

      assert WizardPanel.item_changes(
               %{@same | "name" => "Staff of Zap"}
               |> Map.put("powers_present", "1")
               |> Map.put("powers", "on"),
               @item,
               @powers
             ) == {:error, :bad_item_abilities}
    end

    test "refuses what is not a number, a half that is not a half, and says why" do
      assert WizardPanel.item_changes(%{@same | "cost" => "x"}, @item, nil) ==
               {:error, :bad_item_cost}

      assert WizardPanel.item_changes(%{@same | "attack" => "1.5"}, @item, nil) ==
               {:error, :bad_item_stat}

      assert WizardPanel.item_changes(%{@same | "movement" => "1.3"}, @item, nil) ==
               {:error, :bad_item_stat}

      assert WizardPanel.item_changes(%{@same | "movement" => "-1"}, @item, nil) ==
               {:error, :bad_item_stat}

      assert WizardPanel.item_changes(%{@same | "name" => 5}, @item, nil) ==
               {:error, :bad_item_name}

      assert WizardPanel.error_message(:bad_item_stat) =~ "attack 0-6"
      assert WizardPanel.error_message(:bad_item_name) =~ "1 to 26"
    end

    test "the label names the item and the fields" do
      assert WizardPanel.item_label(@item, name: "Rod", movement: 7, spell_skill: 9, abilities: 1) ==
               "Edited item Staff of Zap: name Rod, movement 3.5, spell skill 9, powers"
    end
  end

  describe "moving items" do
    defp moving_save do
      Mirror.WizardFixture.synthetic()
      |> Mirror.WizardFixture.with_hero([1, 2, -1])
      |> Mirror.WizardFixture.with_items(
        %{
          1 => {"Sword", 0, 1, 100, [0, 0, 0, 0, 0, 0, 0, 0], 0, 0},
          2 => {"Shield", 7, 5, 100, [0, 0, 1, 0, 0, 0, 0, 0], 0, 0},
          3 => {"Amulet", 6, 6, 100, [0, 0, 0, 0, 0, 0, 0, 0], 0, 0},
          9 => {"Spare Shield", 7, 5, 100, [0, 0, 2, 0, 0, 0, 0, 0], 0, 0}
        },
        0,
        [9, 3]
      )
    end

    setup do
      %{d: WizardPanel.details(moving_save(), 1)}
    end

    defp held(d, index),
      do: Enum.find(Enum.flat_map(d.heroes, & &1.item_list) ++ d.vault, &(&1.index == index))

    test "finds where an item is", %{d: d} do
      assert WizardPanel.item_place(d, 1) == {:hero, 0, 0}
      assert WizardPanel.item_place(d, 2) == {:hero, 0, 1}
      assert WizardPanel.item_place(d, 9) == {:vault, 0}
      assert WizardPanel.item_place(d, 3) == {:vault, 1}
      assert WizardPanel.item_place(d, 77) == nil
    end

    test "offers the vault and the hero's empty places of the item's own kind", %{d: d} do
      # the amulet (slot 6) fits the hero's empty third place; the vault is where it is, so not offered
      assert WizardPanel.item_moves(d, held(d, 3)) == [{"hero:0:2", "Harold (misc)"}]

      # the sword and the shield are carried: only the vault has room (a hero's matching place is taken)
      assert WizardPanel.item_moves(d, held(d, 1)) == [{"vault:2", "the vault"}]
      assert WizardPanel.item_moves(d, held(d, 2)) == [{"vault:2", "the vault"}]
      # the spare shield (slot 5) has no free armor place on the hero
      assert WizardPanel.item_moves(d, held(d, 9)) == []
    end

    test "a full vault is not offered", %{d: d} do
      full = %{d | vault_places: [9, 3, 5, 6]}
      assert WizardPanel.item_moves(full, held(d, 1)) == []
    end

    test "reads the move form and refuses what it cannot read", %{d: d} do
      assert WizardPanel.move_request(d, 3, "hero:0:2") == {:ok, {{:vault, 1}, {:hero, 0, 2}}}
      assert WizardPanel.move_request(d, 1, "vault:2") == {:ok, {{:hero, 0, 0}, {:vault, 2}}}
      assert WizardPanel.move_request(d, 77, "vault:2") == {:error, :no_such_item}
      assert WizardPanel.move_request(d, 1, "vault:x") == {:error, :bad_move}
      assert WizardPanel.move_request(d, 1, "hero:0") == {:error, :bad_move}
      assert WizardPanel.move_request(d, 1, "elsewhere") == {:error, :bad_move}
      assert WizardPanel.move_request(d, 1, nil) == {:error, :bad_move}
    end

    test "the label names the item and where it goes", %{d: d} do
      assert WizardPanel.move_label(d, held(d, 3), {:hero, 0, 2}) == "Moved Amulet to Harold"
      assert WizardPanel.move_label(d, held(d, 1), {:vault, 2}) == "Moved Sword to the vault"
      assert WizardPanel.error_message(:wrong_slot) =~ "place of its own kind"
    end
  end

  describe "filling and emptying places" do
    @premade [
      %{
        number: 1,
        name: "Black Asp",
        slot: 1,
        type: 0,
        cost: 250,
        icon: 3,
        stats: <<1, 0, 0, 0, 0, 0, 0, 0>>,
        charges: 0,
        abilities: 0x200,
        slot_name: "melee weapon",
        type_name: "Sword"
      },
      %{
        number: 7,
        name: "Ring of Power",
        slot: 6,
        type: 6,
        cost: 600,
        icon: 4,
        stats: <<0, 0, 2, 1, 2, 5, 0, 0>>,
        charges: 0,
        abilities: 0,
        slot_name: "misc",
        type_name: "Misc"
      },
      %{
        number: 9,
        name: "Another Sword",
        slot: 1,
        type: 0,
        cost: 300,
        icon: 5,
        stats: <<0::64>>,
        charges: 0,
        abilities: 0,
        slot_name: "melee weapon",
        type_name: "Sword"
      }
    ]

    defp place_save do
      Mirror.WizardFixture.synthetic()
      |> Mirror.WizardFixture.with_hero([1, 2, -1])
      |> Mirror.WizardFixture.with_items(
        %{
          1 => {"Sword", 0, 1, 100, [0, 0, 0, 0, 0, 0, 0, 0], 0, 0},
          2 => {"Shield", 7, 5, 100, [0, 0, 1, 0, 0, 0, 0, 0], 0, 0},
          9 => {"Spare Shield", 7, 5, 100, [0, 0, 2, 0, 0, 0, 0, 0], 0, 0}
        },
        0,
        [9]
      )
    end

    setup do
      %{d: WizardPanel.details(place_save(), 1)}
    end

    test "lists the hero's three places and the vault's four, with the slot types", %{d: d} do
      places = WizardPanel.item_places(d)

      assert Enum.map(places, & &1.key) == [
               "hero:0:0",
               "hero:0:1",
               "hero:0:2",
               "vault:0",
               "vault:1",
               "vault:2",
               "vault:3"
             ]

      assert Enum.map(places, & &1.item) == [1, 2, nil, 9, nil, nil, nil]
      assert Enum.map(Enum.take(places, 3), & &1.slot_type) == [1, 5, 6]
      assert Enum.all?(Enum.drop(places, 3), &is_nil(&1.slot_type))
    end

    test "a hero's place offers the premade items of its own kind, the vault all of them", %{d: d} do
      [melee, _armor, misc, vault_taken, vault_empty | _] = WizardPanel.item_places(d)

      assert WizardPanel.place_choices(melee, @premade) == [
               {"keep", "(keep what is there)"},
               {"clear", "(remove the item)"},
               {"item:9", "Another Sword (300 gold)"},
               {"item:1", "Black Asp (250 gold)"}
             ]

      assert WizardPanel.place_choices(misc, @premade) == [
               {"keep", "(empty)"},
               {"item:7", "Ring of Power (600 gold)"}
             ]

      assert length(WizardPanel.place_choices(vault_taken, @premade)) == 2 + 3
      assert length(WizardPanel.place_choices(vault_empty, @premade)) == 1 + 3
    end

    test "reads the form's choice", %{d: d} do
      assert WizardPanel.set_request(d, "hero:0:2", "keep", @premade) == {:ok, nil}

      assert WizardPanel.set_request(d, "hero:0:0", "clear", @premade) ==
               {:ok, {:clear, {:hero, 0, 0}}}

      assert {:ok, {:set, {:hero, 0, 2}, %{name: "Ring of Power"}}} =
               WizardPanel.set_request(d, "hero:0:2", "item:7", @premade)

      assert {:ok, {:set, {:vault, 3}, %{name: "Black Asp"}}} =
               WizardPanel.set_request(d, "vault:3", "item:1", @premade)
    end

    test "refuses a place that is not there, a choice that is not one, a premade number not in the table",
         %{d: d} do
      assert WizardPanel.set_request(d, "hero:3:0", "clear", @premade) == {:error, :bad_move}
      assert WizardPanel.set_request(d, "nowhere", "clear", @premade) == {:error, :bad_move}
      assert WizardPanel.set_request(d, "vault:1", "everything", @premade) == {:error, :bad_move}

      assert WizardPanel.set_request(d, "vault:1", "item:999", @premade) ==
               {:error, :no_such_item}

      assert WizardPanel.set_request(d, "vault:1", "item:x", @premade) == {:error, :no_such_item}
    end

    test "the labels name the item and the owner", %{d: d} do
      assert WizardPanel.set_label(d, {:set, {:hero, 0, 2}, hd(@premade)}, nil) ==
               "Put Black Asp in Harold"

      assert WizardPanel.set_label(d, {:clear, {:vault, 0}}, nil) ==
               "Removed Spare Shield from the vault"

      assert WizardPanel.set_label(d, {:clear, {:hero, 0, 0}}, nil) == "Removed Sword from Harold"
    end
  end
end
