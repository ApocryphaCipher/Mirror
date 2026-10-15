defmodule Mirror.SaveFile.StructuresItemMoveTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.{Heroes, Items, Structures}
  alias Mirror.WizardFixture

  @wizard 0x9E8
  @vault @wizard + 0x120

  # Jafar's hero (list slot 0, slot types 1, 5, 6) holds item 1 (a sword, slot 1) and item 2 (a shield, slot 5);
  # the vault holds item 9 (a shield) and item 3 (an amulet, slot 6), then two empty places. Item 4 is a bow.
  defp raw do
    WizardFixture.synthetic()
    |> WizardFixture.with_hero([1, 2, -1])
    |> WizardFixture.with_items(
      %{
        1 => {"Sword", 0, 1, 100, [0, 0, 0, 0, 0, 0, 0, 0], 0, 0},
        2 => {"Shield", 7, 5, 100, [0, 0, 1, 0, 0, 0, 0, 0], 0, 0},
        3 => {"Amulet", 6, 6, 100, [0, 0, 0, 0, 0, 0, 0, 0], 0, 0},
        4 => {"Bow", 3, 2, 100, [0, 0, 0, 0, 0, 0, 0, 0], 0, 0},
        9 => {"Spare Shield", 7, 5, 100, [0, 0, 2, 0, 0, 0, 0, 0], 0, 0}
      },
      0,
      [9, 3]
    )
  end

  defp places(raw), do: {hero_places(raw), Items.vault_places(raw, 0)}
  defp hero_places(raw), do: raw |> Heroes.for_wizard(0) |> hd() |> Map.fetch!(:item_places)

  test "reads the places with their gaps, and the hero's slot types" do
    assert places(raw()) == {[1, 2, nil], [9, 3, nil, nil]}
    assert raw() |> Heroes.for_wizard(0) |> hd() |> Map.fetch!(:slot_types) == [1, 5, 6]
  end

  test "vault to a hero's place of the right kind: the index moves and nothing else changes" do
    before = raw()
    assert {:ok, new, %{moved: 3}} = Structures.move_item(before, 0, {:vault, 1}, {:hero, 0, 2})
    assert places(new) == {[1, 2, 3], [9, nil, nil, nil]}

    differing =
      for i <- 0..(byte_size(before) - 1), :binary.at(before, i) != :binary.at(new, i), do: i

    # exactly the hero's third item index (list slot 0, place 2) and the vault's second place, two bytes each
    hero_place = @wizard + 0x76 + 16 + 2 * 2
    assert differing == [hero_place, hero_place + 1, @vault + 2, @vault + 3]
    assert byte_size(new) == byte_size(before)
  end

  test "a hero's place to the vault, then back" do
    {:ok, out, _} = Structures.move_item(raw(), 0, {:hero, 0, 1}, {:vault, 3})
    assert places(out) == {[1, nil, nil], [9, 3, nil, 2]}
    {:ok, back, _} = Structures.move_item(out, 0, {:vault, 3}, {:hero, 0, 1})
    assert back == raw()
  end

  test "a swap is two moves through a free place" do
    {:ok, a, _} = Structures.move_item(raw(), 0, {:hero, 0, 1}, {:vault, 2})
    {:ok, b, _} = Structures.move_item(a, 0, {:vault, 0}, {:hero, 0, 1})
    {:ok, c, _} = Structures.move_item(b, 0, {:vault, 2}, {:vault, 0})
    assert places(c) == {[1, 9, nil], [2, 3, nil, nil]}
  end

  test "refusals say why and leave the save alone" do
    r = raw()
    # item 9 is a shield (slot 5), the hero's place 0 is a melee slot (type 1)
    assert Structures.move_item(r, 0, {:vault, 0}, {:hero, 0, 0}) == {:error, :place_taken}
    {:ok, emptied, _} = Structures.move_item(r, 0, {:hero, 0, 0}, {:vault, 2})
    assert Structures.move_item(emptied, 0, {:vault, 0}, {:hero, 0, 0}) == {:error, :wrong_slot}

    assert Structures.move_item(r, 0, {:vault, 0}, {:hero, 0, 1}) == {:error, :place_taken}
    assert Structures.move_item(r, 0, {:hero, 0, 2}, {:vault, 2}) == {:error, :no_item_there}
    assert Structures.move_item(r, 0, {:vault, 2}, {:vault, 3}) == {:error, :no_item_there}
    assert Structures.move_item(r, 0, {:vault, 0}, {:vault, 0}) == {:error, :same_place}
    assert Structures.move_item(r, 0, {:vault, 0}, {:hero, 3, 0}) == {:error, :no_such_hero}
    assert Structures.move_item(r, 0, {:hero, 3, 0}, {:vault, 2}) == {:error, :no_such_hero}
    assert Structures.move_item(r, 0, {:vault, 0}, {:vault, 4}) == {:error, :no_item_there}
    assert Structures.move_item(r, 0, {:vault, 0}, {:hero, 0, 3}) == {:error, :no_item_there}
    assert Structures.move_item(r, 3, {:vault, 0}, {:vault, 2}) == {:error, :no_such_wizard}
    assert Structures.move_item(r, 7, {:vault, 0}, {:vault, 2}) == {:error, :no_such_wizard}

    assert Structures.move_item(<<0, 1>>, 0, {:vault, 0}, {:vault, 2}) ==
             {:error, :no_such_wizard}
  end

  test "an index that points at a free item slot cannot be moved" do
    # the vault's third place holds item 50, whose record has no name
    r = WizardFixture.put_bytes(raw(), @vault + 4, <<50::little-signed-16>>)
    assert Structures.move_item(r, 0, {:vault, 2}, {:vault, 3}) == {:error, :no_item_there}
  end
end
