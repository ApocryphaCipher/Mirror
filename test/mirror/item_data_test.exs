defmodule Mirror.ItemDataTest do
  use ExUnit.Case, async: true

  alias Mirror.ItemData
  alias Mirror.SaveFile.Items
  alias Mirror.WizardFixture

  # A one-entry LBX of premade records: {name, icon, slot, type, cost, stats, charges, abilities}.
  defp item_lbx(items, count \\ nil) do
    count = count || length(items)

    record = fn {name, icon, slot, type, cost, stats, charges, abilities} ->
      String.pad_trailing(name, 30, <<0>>) <>
        <<icon::little-16, slot, type, cost::little-16>> <>
        :binary.list_to_bin(stats) <>
        <<charges::little-16, abilities::little-32>> <> <<1, 2, 3, 4, 5, 6>>
    end

    entry = <<count::little-16, 56::little-16>> <> IO.iodata_to_binary(Enum.map(items, record))
    start = 16

    <<1::little-16, 0xFEAD::little-16, 0::32, start::little-32,
      start + byte_size(entry)::little-32>> <> entry
  end

  @items [
    {"Black Asp", 3, 1, 0, 250, [1, 0, 0, 0, 0, 0, 0, 0], 0, 0x200},
    {"Protection of Ramses", 65, 5, 7, 2100, [0, 0, 6, 4, 0, 0, 0, 0], 0, 0x2008},
    {"", 0, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], 0, 0},
    {"Staff of Zap", 12, 4, 4, 900, [0, 0, 0, 0, 0, 0, 0, 67], 4, 0}
  ]

  test "reads the premade items by their 1-based number, leaving out an empty record" do
    assert {:ok, [a, b, c]} = ItemData.parse(item_lbx(@items))
    assert Enum.map([a, b, c], & &1.number) == [1, 2, 4]

    assert %{
             name: "Black Asp",
             slot: 1,
             slot_name: "melee weapon",
             type: 0,
             type_name: "Sword",
             cost: 250,
             abilities: 0x200
           } = a

    assert %{name: "Protection of Ramses", slot: 5, type_name: "Shield"} = b
    assert %{name: "Staff of Zap", charges: 4, slot_name: "staff or wand"} = c
  end

  test "save_record/1 is the 50-byte save item record, with movement in half points" do
    {:ok, [_, ramses, staff]} = ItemData.parse(item_lbx(@items))
    record = ItemData.save_record(ramses)
    assert byte_size(record) == 50
    # defense 6 stays, movement 4 becomes 8
    assert binary_part(record, 36, 8) == <<0, 0, 6, 8, 0, 0, 0, 0>>

    # and it reads back through the save's own decoder as the same item
    raw = WizardFixture.put_bytes(WizardFixture.synthetic(), 0x6FB8 + 7 * 50, record)

    assert {:ok,
            %{
              name: "Protection of Ramses",
              cost: 2100,
              defense: 6,
              movement: 8,
              abilities: 0x2008
            }} =
             Items.get(raw, 7)

    # the charged spell survives
    assert {:ok, %{spell: 67, charges: 4}} =
             Items.get(
               WizardFixture.put_bytes(
                 WizardFixture.synthetic(),
                 0x6FB8,
                 ItemData.save_record(staff)
               ),
               0
             )
  end

  test "a file that is not an item table is an error, not a crash" do
    assert {:error, _} = ItemData.parse("junk")
    # says 250 records, holds two
    assert {:error, :bad_item_table} = ItemData.parse(item_lbx(Enum.take(@items, 2), 250))
  end
end
