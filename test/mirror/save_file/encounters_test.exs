defmodule Mirror.SaveFile.EncountersTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.Encounters

  @at 0x6628

  defp put(raw, at, bytes) do
    size = byte_size(bytes)
    <<head::binary-size(^at), _::binary-size(^size), tail::binary>> = raw
    head <> bytes <> tail
  end

  defp blank, do: :binary.copy(<<0>>, @at + 102 * 24)

  # Every field gets a different non-zero value, so an offset or width error shows.
  defp record(raw, i) do
    put(
      raw,
      @at + i * 24,
      <<10, 11, 1, 1, 7, 189, 0x35, 180, 0x88, 9, 250::little-signed-16, 120::little-signed-16, 4,
        0x06, 2, 0, 1000::little-signed-16, 2000::little-signed-16, 3000::little-signed-16>>
    )
  end

  test "decodes every field of a record" do
    raw = blank() |> record(5)

    assert [e] = Encounters.all(raw)

    assert %{
             index: 5,
             x: 10,
             y: 11,
             plane: 1,
             intact: true,
             kind: 7,
             gold: 250,
             mana: 120,
             spell_code: 4,
             flags: 6,
             item_count: 2,
             items: [1000, 2000],
             unknown9: 9
           } = e

    # the count byte's nibbles: low is guards left, high the starting count
    assert [%{slot: 1, type: 189, left: 5, start: 3}, %{slot: 2, type: 180, left: 8, start: 8}] =
             e.guards
  end

  test "an empty slot (count byte 0) is not a guard, and a cleared record keeps its guards' types" do
    raw = blank() |> put(@at, <<3, 3, 0, 0, 5, 7, 0, 0, 0>> <> :binary.copy(<<0>>, 15))
    assert [%{intact: false, kind: 5, guards: []}] = Encounters.all(raw)
  end

  test "all-zero slots and records off the map are not listed; lookups find by index and tile" do
    raw =
      blank() |> record(5) |> put(@at + 6 * 24, <<200, 3, 0, 1, 4>> <> :binary.copy(<<0>>, 19))

    assert [%{index: 5}] = Encounters.all(raw)
    assert %{index: 5} = Encounters.get(raw, 5)
    assert Encounters.get(raw, 6) == nil
    assert [%{index: 5}] = Encounters.at(raw, {10, 11, 1})
    assert Encounters.at(raw, {10, 11, 0}) == []
  end

  test "names" do
    assert Encounters.kind_name(0) == "Tower of Wizardry"
    assert Encounters.kind_name(7) == "Abandoned keep"
    assert Encounters.kind_name(3) == "Sorcery node guardians"
    assert Encounters.kind_name(99) == "site 99"
    assert Encounters.lair_kind?(4) and Encounters.lair_kind?(10)
    refute Encounters.lair_kind?(0) or Encounters.lair_kind?(3)
  end

  test "a save too short for the block gives an empty list, not a crash" do
    assert Encounters.all(<<1, 2, 3>>) == []
  end
end
