defmodule Mirror.ItemPowersTest do
  use ExUnit.Case, async: true

  alias Mirror.ItemPowers

  # A one-entry LBX of power records: {name, kind, realm, amount, mask}.
  defp power_lbx(powers, count \\ nil) do
    count = count || length(powers)

    record = fn {name, kind, realm, amount, mask} ->
      String.pad_trailing(name, 22, <<0>>) <> <<kind, realm, amount, 0, mask::little-32>>
    end

    entry =
      <<count::little-16, 30::little-16>> <> IO.iodata_to_binary(Enum.map(powers, record))

    start = 16

    <<1::little-16, 0xFEAD::little-16, 0::32, start::little-32,
      start + byte_size(entry)::little-32>> <> entry
  end

  @powers [
    {"+3 Defense", 2, 0, 3, 0},
    {"Flaming", 9, 2, 2, 0x100000},
    {"Haste", 9, 1, 7, 0x4000},
    {"Regeneration", 9, 0, 6, 0x40},
    {"", 0, 0, 0, 0}
  ]

  test "reads the records, leaving out the empty one" do
    assert {:ok, powers} = ItemPowers.parse(power_lbx(@powers))
    assert Enum.map(powers, & &1.name) == ["+3 Defense", "Flaming", "Haste", "Regeneration"]
    assert %{index: 1, kind: 9, realm: 2, amount: 2, mask: 0x100000} = Enum.at(powers, 1)
  end

  test "names_for/2 lists the special powers whose bit is set; stat powers and unknown bits are ignored" do
    {:ok, powers} = ItemPowers.parse(power_lbx(@powers))
    assert ItemPowers.names_for(powers, 0x100000 + 0x40) == ["Flaming", "Regeneration"]
    assert ItemPowers.names_for(powers, 0x4000) == ["Haste"]
    assert ItemPowers.names_for(powers, 0) == []
    assert ItemPowers.names_for(powers, 0x80000000) == []
  end

  test "a file that is not a power table is an error, not a crash" do
    assert {:error, _} = ItemPowers.parse("junk")
    # says 67 records, holds two
    assert {:error, :bad_power_table} = ItemPowers.parse(power_lbx(Enum.take(@powers, 2), 67))
  end
end
