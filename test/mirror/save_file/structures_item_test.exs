defmodule Mirror.SaveFile.StructuresItemTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.Structures
  alias Mirror.WizardFixture

  @block 0x6FB8

  defp raw do
    WizardFixture.with_items(WizardFixture.synthetic(), %{
      1 => {"Mae Govannon", 0, 1, 1200, [1, 0, 1, 0, 0, 5, 0, 67], 3, 0x4},
      2 => {"Plain Shield", 7, 5, 300, [0, 0, 3, 2, 3, 0, 0, 0], 0, 0x2000}
    })
  end

  defp rec(raw, index), do: binary_part(raw, @block + index * 50, 50)

  test "writes name, cost, stat bytes and powers at their offsets and nothing else" do
    before = raw()

    assert {:ok, new, %{changed: changed}} =
             Structures.edit_item(before, 1,
               name: "Sword of Tests",
               cost: 4000,
               attack: 6,
               to_hit: 3,
               defense: 2,
               movement: 8,
               resistance: 5,
               spell_skill: 20,
               spell_save: 4,
               abilities: 0x2008
             )

    assert length(changed) == 10
    r = rec(new, 1)
    assert binary_part(r, 0, 30) == "Sword of Tests" <> :binary.copy(<<0>>, 16)
    assert binary_part(r, 34, 2) == <<4000::little-16>>
    assert binary_part(r, 36, 7) == <<6, 3, 2, 8, 5, 20, 4>>
    assert binary_part(r, 46, 4) == <<0x2008::little-32>>

    # the charged spell, the charges, the icon, slot and type and every other record are untouched
    assert binary_part(r, 43, 1) == <<67>>
    assert binary_part(r, 44, 2) == <<3::little-16>>
    assert binary_part(r, 30, 4) == binary_part(rec(before, 1), 30, 4)
    assert rec(new, 2) == rec(before, 2)
    assert byte_size(new) == byte_size(before)
  end

  test "a shorter name leaves no tail, and an empty change list changes nothing" do
    {:ok, new, _} = Structures.edit_item(raw(), 1, name: "Al")
    assert binary_part(rec(new, 1), 0, 30) == "Al" <> :binary.copy(<<0>>, 28)
    assert {:ok, same, %{changed: []}} = Structures.edit_item(raw(), 1, [])
    assert same == raw()
  end

  test "refuses bad values, naming the kind, and leaves the save alone" do
    r = raw()
    assert Structures.edit_item(r, 1, name: "") == {:error, :bad_item_name}
    assert Structures.edit_item(r, 1, name: "Zoë") == {:error, :bad_item_name}
    assert Structures.edit_item(r, 1, name: String.duplicate("x", 27)) == {:error, :bad_item_name}
    assert Structures.edit_item(r, 1, cost: 65_536) == {:error, :bad_item_cost}
    assert Structures.edit_item(r, 1, cost: -1) == {:error, :bad_item_cost}
    assert Structures.edit_item(r, 1, attack: 7) == {:error, :bad_item_stat}
    assert Structures.edit_item(r, 1, to_hit: 4) == {:error, :bad_item_stat}
    assert Structures.edit_item(r, 1, movement: 9) == {:error, :bad_item_stat}
    assert Structures.edit_item(r, 1, spell_skill: 21) == {:error, :bad_item_stat}
    assert Structures.edit_item(r, 1, spell_save: -1) == {:error, :bad_item_stat}
    assert Structures.edit_item(r, 1, abilities: 0x1_0000_0000) == {:error, :bad_item_abilities}
    assert Structures.edit_item(r, 1, colour: 1) == {:error, {:unknown_field, :colour}}
    # a refused list writes nothing, even when its first field was fine
    assert Structures.edit_item(r, 1, cost: 5, attack: 99) == {:error, :bad_item_stat}
  end

  test "refuses an index with no item: a free slot, outside the block, or not a number" do
    r = raw()
    assert Structures.edit_item(r, 0, name: "Nobody") == {:error, :no_such_item}
    assert Structures.edit_item(r, 138, name: "Nobody") == {:error, :no_such_item}
    assert Structures.edit_item(r, -1, name: "Nobody") == {:error, :no_such_item}
    assert Structures.edit_item(r, "1", name: "Nobody") == {:error, :no_such_item}
    assert Structures.edit_item(<<0, 1>>, 1, name: "Nobody") == {:error, :no_such_item}
  end
end
