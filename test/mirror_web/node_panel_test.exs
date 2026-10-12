defmodule MirrorWeb.NodePanelTest do
  use ExUnit.Case, async: true

  alias MirrorWeb.NodePanel

  @details %{
    type_name: "Sorcery",
    owner: nil,
    owners: [{0, "Jafar"}, {1, "Freya"}],
    warped: false,
    spirit_meld: false,
    guardians_alive: true
  }

  defp form(extra),
    do: Map.merge(%{"owner" => "", "flags_present" => "1"}, extra)

  test "the form as posted, unchanged, is no change" do
    assert {:ok, []} = NodePanel.changes(form(%{}), @details)
  end

  test "an owner, none, and each flag are changes only when they differ" do
    assert {:ok, [owner: 1]} = NodePanel.changes(form(%{"owner" => "1"}), @details)
    assert {:ok, []} = NodePanel.changes(form(%{"owner" => "1"}), %{@details | owner: 1})
    assert {:ok, [owner: nil]} = NodePanel.changes(form(%{}), %{@details | owner: 1})

    assert {:ok, [warped: true, spirit_meld: true]} =
             NodePanel.changes(form(%{"warped" => "on", "spirit_meld" => "on"}), @details)

    # an unticked box posts nothing
    assert {:ok, [warped: false]} =
             NodePanel.changes(form(%{}), %{@details | warped: true})
  end

  test "without the marker the flags are left alone; an unreadable owner is refused" do
    assert {:ok, []} = NodePanel.changes(%{"owner" => ""}, %{@details | warped: true})
    assert {:error, :bad_owner} = NodePanel.changes(form(%{"owner" => "x"}), @details)
    assert {:error, :bad_owner} = NodePanel.changes(form(%{"owner" => "7"}), @details)
  end

  test "the owner select keeps an unnamed current owner" do
    assert NodePanel.owner_options(%{@details | owner: 3}) ==
             [{0, "Jafar"}, {1, "Freya"}, {3, "Wizard 4"}]

    assert NodePanel.owner_options(%{@details | owner: 1}) == [{0, "Jafar"}, {1, "Freya"}]
  end

  test "giving a node an owner clears its living guardians" do
    assert NodePanel.melding_clears_guardians?(@details, owner: 0)
    refute NodePanel.melding_clears_guardians?(@details, owner: nil)
    refute NodePanel.melding_clears_guardians?(@details, warped: true)
    refute NodePanel.melding_clears_guardians?(%{@details | guardians_alive: false}, owner: 0)
  end

  test "labels say what changed" do
    assert NodePanel.label(@details, owner: 1) == "Gave the Sorcery node to Freya"
    assert NodePanel.label(@details, owner: nil) == "Took away the Sorcery node's melder"
    assert NodePanel.label(@details, warped: true) == "Warped the Sorcery node"
    assert NodePanel.label(@details, owner: 1, warped: true) == "Edited the Sorcery node"
  end
end
