defmodule MirrorWeb.UnitPanelTest do
  use ExUnit.Case, async: true

  alias MirrorWeb.UnitPanel

  test "empty fields are left alone, filled ones are changes in a fixed order" do
    assert {:ok, []} = UnitPanel.changes(%{"level" => "", "owner" => ""})
    assert {:ok, []} = UnitPanel.changes(nil)

    assert {:ok, [level: 2, experience: 60, damage: 0, owner: 5]} =
             UnitPanel.changes(%{
               "owner" => "5",
               "damage" => " 0 ",
               "experience" => "60",
               "level" => "2"
             })
  end

  test "unreadable text is refused, not skipped" do
    assert {:error, :bad_level} = UnitPanel.changes(%{"level" => "x"})
    assert {:error, :bad_experience} = UnitPanel.changes(%{"experience" => "1.5"})
    assert {:error, :bad_damage} = UnitPanel.changes(%{"damage" => "-"})
    assert {:error, :bad_owner} = UnitPanel.changes(%{"owner" => "one"})
  end

  test "the label names what was set" do
    assert UnitPanel.label(1, [level: 3], %{}) == "Edited 1 unit: level 3"

    assert UnitPanel.label(2, [experience: 20, owner: 1], %{1 => "Freya"}) ==
             "Edited 2 units: 20 xp, owner Freya"

    assert UnitPanel.label(2, [owner: 5], %{}) == "Edited 2 units: owner Neutral"
  end
end
