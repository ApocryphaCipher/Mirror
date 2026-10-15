defmodule MirrorWeb.LairPanelTest do
  use ExUnit.Case, async: true

  alias MirrorWeb.LairPanel

  # An abandoned keep: 3 of 5 Barbarian Spearmen (type 39) left, nothing in slot 2, 120 gold, 40 mana.
  @details %{
    kind_name: "Abandoned keep",
    intact: true,
    slots: [
      %{slot: 1, type: 39, name: "Barbarian Spearmen", left: 3, start: 5},
      %{slot: 2, type: nil, name: nil, left: nil, start: nil}
    ],
    gold: 120,
    mana: 40,
    item_count: 1
  }

  defp form(extra) do
    Map.merge(
      %{
        "intact_present" => "1",
        "intact" => "on",
        "guard1_type" => "39",
        "guard1_count" => "3",
        "guard2_type" => "",
        "guard2_count" => "1",
        "gold" => "120",
        "mana" => "40",
        "item_count" => "1"
      },
      extra
    )
  end

  test "the form as posted, unchanged, is no change (a half-fought guard keeps its count)" do
    assert {:ok, []} = LairPanel.changes(form(%{}), @details)
  end

  test "each field is a change when it differs" do
    assert {:ok, [intact: false]} =
             LairPanel.changes(Map.delete(form(%{}), "intact"), @details)

    assert {:ok, [gold: 5]} = LairPanel.changes(form(%{"gold" => "5"}), @details)
    assert {:ok, [mana: 0]} = LairPanel.changes(form(%{"mana" => "0"}), @details)
    assert {:ok, [item_count: 3]} = LairPanel.changes(form(%{"item_count" => "3"}), @details)

    assert {:ok, [guards: %{1 => {39, 8}}]} =
             LairPanel.changes(form(%{"guard1_count" => "8"}), @details)

    assert {:ok, [guards: %{1 => {196, 3}}]} =
             LairPanel.changes(form(%{"guard1_type" => "196"}), @details)

    assert {:ok, [guards: %{2 => {196, 2}}]} =
             LairPanel.changes(form(%{"guard2_type" => "196", "guard2_count" => "2"}), @details)

    assert {:ok, [guards: %{1 => nil}]} =
             LairPanel.changes(form(%{"guard1_type" => ""}), @details)
  end

  test "a malformed intact value is refused, not read as unticked" do
    for bad <- ["garbage", "", "off", "1", ["on"], %{"x" => "on"}] do
      assert {:error, :bad_intact} = LairPanel.changes(form(%{"intact" => bad}), @details),
             "expected #{inspect(bad)} to be refused"
    end

    # the documented values, and the missing key, still mean ticked and unticked
    assert {:ok, []} = LairPanel.changes(form(%{"intact" => "true"}), @details)
    assert {:ok, [intact: false]} = LairPanel.changes(Map.delete(form(%{}), "intact"), @details)
  end

  test "an empty slot posted as empty is no change, whatever its count box says" do
    assert {:ok, []} =
             LairPanel.changes(form(%{"guard2_type" => "", "guard2_count" => "7"}), @details)
  end

  test "unreadable values are refused, not skipped" do
    for bad <- [%{"gold" => "x"}, %{"gold" => ""}, %{"gold" => ["1"]}] do
      assert {:error, :bad_gold} = LairPanel.changes(form(bad), @details)
    end

    assert {:error, :bad_mana} = LairPanel.changes(form(%{"mana" => "1.5"}), @details)
    assert {:error, :bad_guards} = LairPanel.changes(form(%{"guard1_type" => "x"}), @details)
    assert {:error, :bad_guards} = LairPanel.changes(form(%{"guard1_count" => ""}), @details)
    assert {:error, :bad_guards} = LairPanel.changes(form(%{"guard1_type" => ["39"]}), @details)
  end

  test "a form with none of the fields changes nothing" do
    assert {:ok, []} = LairPanel.changes(%{}, @details)
  end

  test "labels say what happened" do
    assert LairPanel.label(@details, intact: false) == "Cleared the abandoned keep"
    assert LairPanel.label(@details, intact: true) == "Restored the abandoned keep"
    assert LairPanel.label(@details, gold: 5) == "Set the abandoned keep's gold to 5"

    assert LairPanel.label(@details, guards: %{1 => {196, 3}, 2 => nil}) ==
             "Changed the abandoned keep's guards (3 Sky Drake, -guard)"

    assert LairPanel.label(@details, gold: 5, mana: 1) == "Edited the abandoned keep"
  end

  test "the unit select lists all 198 types" do
    assert length(LairPanel.unit_type_options()) == 198
    assert {196, "Sky Drake"} in LairPanel.unit_type_options()
  end

  test "the item count must be a whole number the record can hold" do
    for bad <- ["x", "", "1.5"] do
      assert {:error, :bad_item_count} = LairPanel.changes(form(%{"item_count" => bad}), @details)
    end

    # a number outside 0 to 3 is refused by the save code, which knows the record
    assert LairPanel.error_message(:bad_item_count) =~ "0 to 3"
    assert LairPanel.label(@details, item_count: 2) =~ "items to roll to 2"
  end
end
