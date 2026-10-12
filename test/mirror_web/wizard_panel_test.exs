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
end
