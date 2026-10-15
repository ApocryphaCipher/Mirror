defmodule Mirror.SaveFile.StructuresHeroAddTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.{HeroTypes, Heroes, Structures, Units}
  alias Mirror.WizardFixture

  @units 0x00B734

  # Jafar (record 0) has his summoning circle at (38, 21) on Myrror; the game writes -1 in empty hero entries.
  defp raw do
    empty = <<-1::little-signed-16>> <> :binary.copy(<<0>>, 26)

    Enum.reduce(0..4, WizardFixture.synthetic(), fn w, acc ->
      WizardFixture.field(acc, w, 0x76, :binary.copy(empty, 6))
    end)
  end

  test "a new hero gets a unit, a list entry, the hired mark and, for the player, a name" do
    before = raw()
    assert {:ok, new, %{added: 31, unit: 0, slot: 0}} = Structures.add_hero(before, 0, 0, 31)

    assert [hero] = Heroes.for_wizard(new, 0)

    assert %{
             slot: 0,
             unit_index: 0,
             name: "Sir Harold",
             type: 31,
             level: 1,
             experience: 1,
             damage: 0,
             location: %{x: 38, y: 21, plane: :myrror},
             items: [],
             item_places: [nil, nil, nil],
             slot_types: [1, 5, 6],
             hired_marker: -20
           } = hero

    # the unit record, byte for byte
    assert binary_part(new, @units, 32) ==
             <<38, 21, 1, 0, 4, 31, 0, 0, 4, 0, 0, 0, 1, 0, 1, 0, 0, 0, 8, 0, 0, 0, 1, 0, 0, 0, 0,
               0, 255, 0, 0, 0>>

    assert {:ok, [unit]} = Units.parse(new)
    assert %{type: 31, owner: 0} = unit
    assert binary_part(new, 0x9E2, 2) == <<1::little-16>>

    # the name table at the end of the save: 35 x (14-byte name + experience)
    names = byte_size(new) - 560
    assert binary_part(new, names + 31 * 16, 16) == "Sir Harold" <> <<0, 0, 0, 0>> <> <<0, 0>>

    # nothing else changed
    differing =
      for i <- 0..(byte_size(before) - 1), :binary.at(before, i) != :binary.at(new, i), do: i

    allowed =
      Enum.to_list(@units..(@units + 31)) ++
        [0x9E2, 0x9E3] ++
        Enum.to_list((0x9E8 + 0x76)..(0x9E8 + 0x76 + 27)) ++
        [31 * 12, 31 * 12 + 1] ++ Enum.to_list((names + 31 * 16)..(names + 31 * 16 + 15))

    assert Enum.all?(differing, &(&1 in allowed))
    assert 0x9E2 in differing
  end

  test "a rival's hero is not written into the player's name table" do
    rival =
      raw()
      |> WizardFixture.field(1, 0x2E, <<10::little-16, 12::little-16, 0::little-16>>)

    assert {:ok, new, _} = Structures.add_hero(rival, 1, 2, 6)
    names = byte_size(new) - 560
    assert binary_part(new, names + 6 * 16, 16) == :binary.copy(<<0>>, 16)
    assert binary_part(new, 1 * 420 + 6 * 12, 2) == <<-20::little-signed-16>>

    assert [%{slot: 2, name: "Bahgtru", location: %{x: 10, y: 12, plane: :arcanus}}] =
             Heroes.for_wizard(new, 1)
  end

  test "each hero type has the slot kinds the saves show: fighter, mage, archer, any weapon" do
    for {type, kinds} <- [{31, [1, 5, 6]}, {2, [4, 6, 6]}, {3, [2, 5, 6]}, {33, [3, 5, 6]}] do
      {:ok, new, _} = Structures.add_hero(raw(), 0, 0, type)
      assert [%{slot_types: ^kinds}] = Heroes.for_wizard(new, 0)
      assert HeroTypes.slot_types(type) == kinds
    end
  end

  test "a second hero takes the next unit index and its own slot" do
    {:ok, one, _} = Structures.add_hero(raw(), 0, 0, 31)
    {:ok, two, %{unit: 1}} = Structures.add_hero(one, 0, 3, 33)
    assert [%{slot: 0, type: 31}, %{slot: 3, type: 33, unit_index: 1}] = Heroes.for_wizard(two, 0)
    assert binary_part(two, 0x9E2, 2) == <<2::little-16>>
  end

  test "refusals say why, and write nothing" do
    r = raw()
    assert Structures.add_hero(r, 0, 0, 35) == {:error, :bad_hero_type}
    assert Structures.add_hero(r, 0, 0, -1) == {:error, :bad_hero_type}
    assert Structures.add_hero(r, 0, 6, 31) == {:error, :slot_taken}
    assert Structures.add_hero(r, 7, 0, 31) == {:error, :no_such_wizard}
    assert Structures.add_hero(<<0, 1>>, 0, 0, 31) == {:error, :no_such_wizard}

    # a wizard whose summoning circle is not on the map (x 99)
    off_map = WizardFixture.field(r, 1, 0x2E, <<99::little-16, 12::little-16, 0::little-16>>)
    assert Structures.add_hero(off_map, 1, 0, 31) == {:error, :no_circle}

    {:ok, taken, _} = Structures.add_hero(r, 0, 0, 31)
    assert Structures.add_hero(taken, 0, 0, 33) == {:error, :slot_taken}
    assert Structures.add_hero(taken, 0, 1, 31) == {:error, :hero_in_play}
  end

  test "a hero of any owner, a full tile and a full unit table are refused" do
    # a rival's Bahgtru is a live unit: the type is in play
    rival_hero =
      raw()
      |> WizardFixture.put_bytes(@units, <<5, 5, 0, 1, 4, 6, 0, 0, 4>> <> :binary.copy(<<0>>, 23))
      |> WizardFixture.put_bytes(0x9E2, <<1::little-16>>)

    assert Structures.add_hero(rival_hero, 0, 0, 6) == {:error, :hero_in_play}

    # nine of his units already stand on the circle (38, 21, Myrror)
    nine =
      Enum.reduce(0..8, raw(), fn i, acc ->
        WizardFixture.put_bytes(
          acc,
          @units + i * 32,
          <<38, 21, 1, 0, 2, 120>> <> :binary.copy(<<0>>, 26)
        )
      end)
      |> WizardFixture.put_bytes(0x9E2, <<9::little-16>>)

    assert Structures.add_hero(nine, 0, 0, 31) == {:error, :stack_full}

    full = WizardFixture.put_bytes(raw(), 0x9E2, <<1009::little-16>>)
    assert Structures.add_hero(full, 0, 0, 31) == {:error, :no_free_unit}
  end
end
