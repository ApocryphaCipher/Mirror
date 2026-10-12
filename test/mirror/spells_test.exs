defmodule Mirror.SpellsTest do
  use ExUnit.Case, async: true

  alias Mirror.Spells

  # A one-entry LBX holding `count` spell records of 36 bytes; record n is named by `names`.
  defp spell_lbx(names, count \\ 215) do
    record = fn n ->
      {name, realm, cost, research} = Map.get(names, n, {"", 0, 0, 0})

      String.pad_trailing(name, 18, <<0>>) <>
        <<0, 0, 0, 0, 0, realm, 0, 0, cost::little-16, research::little-16>> <>
        :binary.copy(<<0>>, 36 - 18 - 5 - 1 - 2 - 4)
    end

    entry =
      <<count::little-16, 36::little-16>> <>
        IO.iodata_to_binary(for n <- 0..(count - 1), do: record.(n))

    start = 8 + 2 * 4

    <<1::little-16, 0xFEAD::little-16, 0::32, start::little-32,
      start + byte_size(entry)::little-32>> <> entry
  end

  test "reads names, realms and costs by spell number" do
    raw =
      spell_lbx(%{
        1 => {"Earth to Mud", 0, 15, 20},
        98 => {"Raise Volcano", 2, 200, 680},
        214 => {"Spell of Return", 5, 1000, 20}
      })

    assert {:ok, table} = Spells.parse(raw)
    assert map_size(table) == 214
    assert table[1] == %{number: 1, name: "Earth to Mud", realm: :nature, cost: 15, research: 20}
    assert %{name: "Raise Volcano", realm: :chaos, cost: 200, research: 680} = table[98]
    assert %{realm: :arcane} = table[214]
    refute Map.has_key?(table, 0)
  end

  test "a file that is not a spell table is an error, not a crash" do
    assert {:error, _} = Spells.parse("junk")

    # the entry says 215 records of 36 bytes but holds ten
    entry = <<215::little-16, 36::little-16>> <> :binary.copy(<<0>>, 360)
    start = 16

    short =
      <<1::little-16, 0xFEAD::little-16, 0::32, start::little-32,
        start + byte_size(entry)::little-32>> <> entry

    assert Spells.parse(short) == {:error, :bad_spell_table}

    # a record size other than 36
    odd = <<215::little-16, 20::little-16>> <> :binary.copy(<<0>>, 4300)

    odd_lbx =
      <<1::little-16, 0xFEAD::little-16, 0::32, start::little-32,
        start + byte_size(odd)::little-32>> <> odd

    assert Spells.parse(odd_lbx) == {:error, :bad_spell_table}
  end

  test "name/2 falls back to the number without a table" do
    assert Spells.name(nil, 19) == "Spell 19"
    assert Spells.name(%{}, 19) == "Spell 19"
    assert Spells.name(%{19 => %{name: "Nature's Cures"}}, 19) == "Nature's Cures"
  end
end
