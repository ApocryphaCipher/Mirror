defmodule Mirror.SaveFile.ItemsTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.Items
  alias Mirror.WizardFixture

  @block 0x6FB8

  # name, icon, slot, type, cost, the eight stat bytes, charges, abilities
  defp record(name, opts) do
    stats = Keyword.get(opts, :stats, [0, 0, 0, 0, 0, 0, 0, 0])

    String.pad_trailing(name, 30, <<0>>) <>
      <<Keyword.get(opts, :icon, 0)::little-16, Keyword.fetch!(opts, :slot),
        Keyword.fetch!(opts, :type), Keyword.get(opts, :cost, 0)::little-16>> <>
      :binary.list_to_bin(stats) <>
      <<Keyword.get(opts, :charges, 0)::little-16, Keyword.get(opts, :abilities, 0)::little-32>>
  end

  defp raw do
    WizardFixture.synthetic()
    |> WizardFixture.put_bytes(
      @block + 1 * 50,
      record("Mae Govannon",
        slot: 1,
        type: 0,
        cost: 1200,
        stats: [1, 0, 1, 0, 0, 5, 0, 0],
        abilities: 4
      )
    )
    |> WizardFixture.put_bytes(
      @block + 2 * 50,
      record("Staff of Zap",
        slot: 4,
        type: 4,
        cost: 900,
        stats: [0, 0, 0, 0, 0, 0, 0, 67],
        charges: 4,
        icon: 12
      )
    )
    # slot 3 has a name-less record with leftover bytes: a free slot
    |> WizardFixture.put_bytes(
      @block + 3 * 50,
      <<0::240>> <> <<9, 9, 9, 9>> <> :binary.copy(<<0>>, 16)
    )
    |> WizardFixture.put_bytes(@block + 137 * 50, record("Last One", slot: 6, type: 6, cost: 5))
    |> WizardFixture.field(
      0,
      0x120,
      <<2::little-signed-16, -1::little-signed-16, 137::little-signed-16, -1::little-signed-16>>
    )
  end

  test "reads the items in use with their fields, in index order" do
    assert {:ok, [a, b, c]} = Items.parse(raw())
    assert Enum.map([a, b, c], & &1.index) == [1, 2, 137]

    assert %{
             name: "Mae Govannon",
             slot: 1,
             slot_name: "melee weapon",
             type: 0,
             type_name: "Sword",
             cost: 1200,
             attack: 1,
             to_hit: 0,
             defense: 1,
             resistance: 0,
             spell_skill: 5,
             abilities: 4
           } = a

    assert %{type_name: "Staff", spell: 67, charges: 4, icon: 12, slot_name: "staff or wand"} = b
    assert %{name: "Last One", slot_name: "misc"} = c
  end

  test "get/2: an item, a free slot, and an index outside the block" do
    assert {:ok, %{name: "Mae Govannon"}} = Items.get(raw(), 1)
    assert Items.get(raw(), 0) == :free
    assert Items.get(raw(), 3) == :free
    assert Items.get(raw(), 138) == :error
    assert Items.get(raw(), -1) == :error
    assert Items.get(<<0, 1>>, 1) == :error
  end

  test "for_indexes/2 keeps the list's order and leaves out free slots and bad indexes" do
    names = raw() |> Items.for_indexes([137, 0, 2, 999, 1]) |> Enum.map(& &1.name)
    assert names == ["Last One", "Staff of Zap", "Mae Govannon"]
  end

  test "vault/2 lists the occupied places of a wizard's vault" do
    assert Items.vault(raw(), 0) == [2, 137]
    # the game writes -1 in every empty place (a zeroed record would read as item 0)
    empty = WizardFixture.field(raw(), 1, 0x120, :binary.copy(<<-1::little-signed-16>>, 4))
    assert Items.vault(empty, 1) == []
    assert Items.vault(raw(), 5) == []
    assert Items.vault(<<>>, 0) == []
  end

  test "a save too short for the block gives an error, not a crash" do
    assert Items.parse(<<0, 1, 2>>) == {:error, :no_items_block}
    assert Items.parse(:binary.copy(<<0>>, 0x6FB8 + 100)) == {:error, :no_items_block}
  end

  test "type and slot names follow the Create Artifact screen's codes" do
    assert Enum.map(0..9, &Items.type_name/1) ==
             ~w(Sword Mace Axe Bow Staff Wand Misc Shield Chain Plate)

    assert Items.type_name(10) == nil
    assert Items.slot_name(3) == "any weapon"
    assert Items.slot_name(7) == nil
    assert Items.slot_name(5) == "armor"
  end

  test "an any-weapon place (type 3) takes a melee weapon, a bow or a staff, other places only their own kind" do
    for item_slot <- [1, 2, 4], do: assert(Items.slot_accepts?(3, item_slot))
    refute Items.slot_accepts?(3, 5)
    refute Items.slot_accepts?(3, 6)
    assert Items.slot_accepts?(5, 5)
    refute Items.slot_accepts?(1, 2)
    refute Items.slot_accepts?(4, 1)
  end
end
