defmodule MirrorWeb.WizardPanelTest do
  use ExUnit.Case, async: true

  alias MirrorWeb.WizardPanel

  @offset 0x9E8
  @record 0x4C8

  defp put(raw, at, bytes) do
    size = byte_size(bytes)
    <<head::binary-size(^at), _::binary-size(^size), tail::binary>> = raw
    head <> bytes <> tail
  end

  defp field(raw, record, at, bytes), do: put(raw, @offset + record * @record + at, bytes)

  # A zeroed save with Jafar (record 0, blue) and a rival (record 1, red).
  def synthetic do
    # Unused node records are 0xFF, as in the game (a zeroed one is a node owned by wizard 0).
    raw = put(:binary.copy(<<0>>, 123_300), 0x6058, :binary.copy(<<0xFF>>, 30 * 48))

    raw
    |> field(0, 0x00, <<7>>)
    |> field(0, 0x01, String.pad_trailing("Jafar", 20, <<0>>))
    |> field(0, 0x16, <<0>>)
    |> field(0, 0x24, <<10::little-16, 12::little-16>>)
    |> field(0, 0x2A, <<34, 33, 33>>)
    |> field(0, 0x2E, <<38::little-16, 21::little-16, 1::little-16>>)
    |> field(0, 0x54, <<5::little-16, 60::little-16, 2::little-16>>)
    |> field(0, 0x5A, <<0::little-16, 12::little-16, 0::little-16, 3::little-16, 0::little-16>>)
    |> field(0, 0x64 + 0, <<1>>)
    |> field(0, 0x64 + 13, <<1>>)
    |> field(0, 0x25A, <<383::little-16, 500::little-16, 0::little-16, 19::little-16>>)
    |> field(0, 0x264, <<2, 2, 1>>)
    |> field(0, 0x264 + 40, <<2>>)
    |> field(0, 0x356, <<1234::little-16>>)
    |> field(1, 0x01, String.pad_trailing("Sharee", 20, <<0>>))
    |> field(1, 0x16, <<3>>)
  end

  test "reads the fields of wizard 1 as the page shows them" do
    d = WizardPanel.details(synthetic(), 1)

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
             {"Nature", 2},
             {"Sorcery", 1},
             {"Chaos", 0},
             {"Life", 0},
             {"Death", 0},
             {"Arcane", 0}
           ]

    assert d.standing == %{cities: 0, units: 0, nodes: 0}
  end

  test "a rival is wizard 2; its banner picks the colour" do
    d = WizardPanel.details(synthetic(), 2)
    assert d.name == "Sharee"
    assert d.banner == :red
    assert d.colour == WizardPanel.colour(:red)
  end

  test "no such wizard: nameless record, neutral player, out of range, wrong type" do
    raw = synthetic()
    assert WizardPanel.details(raw, 3) == nil
    assert WizardPanel.details(raw, 6) == nil
    assert WizardPanel.details(raw, 0) == nil
    assert WizardPanel.details(raw, 99) == nil
    assert WizardPanel.details(raw, "1") == nil
    assert WizardPanel.details(<<1, 2, 3>>, 1) == nil
  end

  test "wizards/1 lists the named wizards by page number; page_id maps owners" do
    assert WizardPanel.wizards(synthetic()) == [{1, "Jafar"}, {2, "Sharee"}]
    assert WizardPanel.wizards(nil) == []
    assert WizardPanel.page_id(0) == 1
    assert WizardPanel.page_id(4) == 5
    assert WizardPanel.page_id(5) == nil
    assert WizardPanel.page_id(nil) == nil
  end
end
