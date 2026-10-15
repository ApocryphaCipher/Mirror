defmodule Mirror.SaveFile.StructuresHeroTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.Structures
  alias Mirror.WizardFixture

  @list 0x9E8 + 0x76
  @unit 0x00B734 + 32

  defp raw, do: WizardFixture.with_hero(WizardFixture.synthetic())

  test "writes the name into the list entry and level, experience and damage into the unit, nothing else" do
    before = raw()

    assert {:ok, new, %{changed: [:name, :level, :experience, :damage]}} =
             Structures.edit_hero(before, 0, 0,
               name: "Sir Harold",
               level: 4,
               experience: 300,
               damage: 0
             )

    assert binary_part(new, @list + 2, 14) == "Sir Harold" <> <<0, 0, 0, 0>>
    assert binary_part(new, @unit + 12, 1) == <<4>>
    assert binary_part(new, @unit + 14, 2) == <<300::little-16>>
    assert binary_part(new, @unit + 17, 1) == <<0>>

    # a shorter name leaves no tail of the old one
    {:ok, shorter, _} = Structures.edit_hero(new, 0, 0, name: "Al")
    assert binary_part(shorter, @list + 2, 14) == "Al" <> :binary.copy(<<0>>, 12)

    # only those bytes differ
    differing =
      for i <- 0..(byte_size(before) - 1),
          :binary.at(before, i) != :binary.at(new, i),
          do: i

    assert Enum.all?(
             differing,
             &(&1 in (@list + 2)..(@list + 15) or
                 &1 in [@unit + 12, @unit + 14, @unit + 15, @unit + 17])
           )
  end

  test "a unit-only edit leaves the name alone, and an empty change list changes nothing" do
    {:ok, new, %{changed: [:experience]}} = Structures.edit_hero(raw(), 0, 0, experience: 99)
    assert binary_part(new, @list + 2, 14) == binary_part(raw(), @list + 2, 14)
    assert {:ok, same, _} = Structures.edit_hero(raw(), 0, 0, [])
    assert same == raw()
  end

  test "refuses bad values and says why, leaving the save alone" do
    r = raw()
    assert Structures.edit_hero(r, 0, 0, name: "") == {:error, :bad_hero_name}
    assert Structures.edit_hero(r, 0, 0, name: "Zoë") == {:error, :bad_hero_name}
    assert Structures.edit_hero(r, 0, 0, name: "FourteenChars!") == {:error, :bad_hero_name}
    assert Structures.edit_hero(r, 0, 0, level: 10) == {:error, :bad_level}
    assert Structures.edit_hero(r, 0, 0, experience: -1) == {:error, :bad_experience}
    assert Structures.edit_hero(r, 0, 0, damage: 256) == {:error, :bad_damage}
    assert Structures.edit_hero(r, 0, 0, colour: 1) == {:error, {:unknown_field, :colour}}
    # an owner change is not built here: a hero is in his wizard's list
    assert Structures.edit_hero(r, 0, 0, owner: 2) == {:error, :hero_owner}
  end

  test "refuses an empty slot, a slot out of range and a wizard that does not exist" do
    r = raw()
    assert Structures.edit_hero(r, 0, 1, name: "Nobody") == {:error, :no_such_hero}
    assert Structures.edit_hero(r, 0, 6, name: "Nobody") == {:error, :no_such_wizard}
    assert Structures.edit_hero(r, 7, 0, name: "Nobody") == {:error, :no_such_wizard}
    assert Structures.edit_hero(r, 4, 0, name: "Nobody") == {:error, :no_such_wizard}
  end
end
