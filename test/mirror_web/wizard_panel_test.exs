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
end
