defmodule Mirror.SaveFile.StructuresItemSetTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.{Heroes, Items, Structures}
  alias Mirror.WizardFixture

  @block 0x6FB8

  # The hero (list slot 0, slot types 1, 5, 6) holds item 1 (a sword) and item 2 (a shield) with the misc place
  # empty; the vault holds item 9 (a shield) and item 2 again is NOT shared. Items 0, 3, 4 and so on are free.
  # The game writes -1 in every empty hero entry and vault place; a zeroed fixture would read as unit 0 and item 0, and
  # item 0 would then look referenced. The other four wizards get real empty lists.
  defp realistic(raw) do
    empty_entry = <<-1::little-signed-16>> <> :binary.copy(<<0>>, 26)
    minus_ones = :binary.copy(<<-1::little-signed-16>>, 4)

    Enum.reduce(1..4, raw, fn w, acc ->
      acc
      |> WizardFixture.field(w, 0x76, :binary.copy(empty_entry, 6))
      |> WizardFixture.field(w, 0x120, minus_ones)
    end)
  end

  defp raw do
    realistic(WizardFixture.synthetic())
    |> WizardFixture.with_hero([1, 2, -1])
    |> WizardFixture.with_items(
      %{
        1 => {"Sword", 0, 1, 100, [0, 0, 0, 0, 0, 0, 0, 0], 0, 0},
        2 => {"Shield", 7, 5, 100, [0, 0, 1, 0, 0, 0, 0, 0], 0, 0},
        9 => {"Spare Shield", 7, 5, 100, [0, 0, 2, 0, 0, 0, 0, 0], 0, 0}
      },
      0,
      [9]
    )
  end

  # a save item record: name, icon, slot, type, cost, stats, charges, abilities
  defp record(name, slot, type, cost \\ 500) do
    String.pad_trailing(name, 30, <<0>>) <>
      <<7::little-16, slot, type, cost::little-16, 0, 0, 3, 2, 0, 0, 0, 0, 0::little-16,
        0::little-32>>
  end

  defp places(raw),
    do:
      {raw |> Heroes.for_wizard(0) |> hd() |> Map.fetch!(:item_places),
       Items.vault_places(raw, 0)}

  defp rec(raw, index), do: binary_part(raw, @block + index * 50, 50)

  test "an empty place takes the record into the first free one and points at it" do
    before = raw()

    assert {:ok, new, %{set: 0}} =
             Structures.put_item(before, 0, {:hero, 0, 2}, record("Amulet", 6, 6))

    assert places(new) == {[1, 2, 0], [9, nil, nil, nil]}
    assert rec(new, 0) == record("Amulet", 6, 6)
    # nothing else changed: the new record (item 0's 50 bytes) and the place's two bytes
    differing =
      for i <- 0..(byte_size(before) - 1), :binary.at(before, i) != :binary.at(new, i), do: i

    place = 0x9E8 + 0x76 + 16 + 4
    assert Enum.all?(differing, &(&1 in [place, place + 1] or &1 in @block..(@block + 49)))
    assert place in differing
  end

  test "a place holding an item nothing else shares has its record overwritten in place" do
    {:ok, new, %{set: 2}} =
      Structures.put_item(raw(), 0, {:hero, 0, 1}, record("Plate", 5, 9, 1750))

    assert places(new) == {[1, 2, nil], [9, nil, nil, nil]}
    assert rec(new, 2) == record("Plate", 5, 9, 1750)
    # no other record was touched
    assert rec(new, 1) == rec(raw(), 1)
    assert rec(new, 0) == rec(raw(), 0)
  end

  test "an item two places share is left alone and the new one gets a free record" do
    # the vault's first place also points at item 2
    shared = WizardFixture.field(raw(), 0, 0x120, <<2::little-signed-16>>)

    {:ok, new, %{set: free}} =
      Structures.put_item(shared, 0, {:hero, 0, 1}, record("Plate", 5, 9))

    assert free == 0
    assert rec(new, 2) == rec(shared, 2)
    assert places(new) == {[1, 0, nil], [2, nil, nil, nil]}
  end

  test "a vault place takes any kind" do
    {:ok, new, _} = Structures.put_item(raw(), 0, {:vault, 2}, record("Amulet", 6, 6))
    assert places(new) == {[1, 2, nil], [9, nil, 0, nil]}
  end

  test "a dangling index (a place pointing at a free record) gets a record of its own" do
    dangling = WizardFixture.field(raw(), 0, 0x120 + 2, <<40::little-signed-16>>)

    {:ok, new, %{set: set}} =
      Structures.put_item(dangling, 0, {:vault, 1}, record("Amulet", 6, 6))

    assert set in [0, 40]
    assert Items.get(new, set) |> elem(0) == :ok
  end

  test "refusals say why" do
    r = raw()

    assert Structures.put_item(r, 0, {:hero, 0, 0}, record("Amulet", 6, 6)) ==
             {:error, :wrong_slot}

    assert Structures.put_item(r, 0, {:hero, 3, 0}, record("Amulet", 6, 6)) ==
             {:error, :no_such_hero}

    assert Structures.put_item(r, 0, {:vault, 4}, record("Amulet", 6, 6)) ==
             {:error, :no_item_there}

    assert Structures.put_item(r, 7, {:vault, 0}, record("Amulet", 6, 6)) ==
             {:error, :no_such_wizard}

    assert Structures.put_item(r, 0, {:vault, 0}, <<1, 2, 3>>) == {:error, :bad_item_record}

    assert Structures.put_item(r, 0, {:vault, 0}, :binary.copy(<<0>>, 50)) ==
             {:error, :bad_item_record}
  end

  test "no free record left" do
    full =
      Enum.reduce(0..137, raw(), fn i, acc ->
        if :binary.at(acc, @block + i * 50) == 0,
          do: WizardFixture.put_bytes(acc, @block + i * 50, record("Filler #{i}", 6, 6)),
          else: acc
      end)

    assert Structures.put_item(full, 0, {:hero, 0, 2}, record("Amulet", 6, 6)) ==
             {:error, :no_free_item}

    # overwriting a place's own item still works with no free record
    assert {:ok, _, %{set: 1}} = Structures.put_item(full, 0, {:hero, 0, 0}, record("Axe", 1, 2))
  end

  test "clear_item empties the place and blanks a record nothing else points at" do
    {:ok, new, %{cleared: 9}} = Structures.clear_item(raw(), 0, {:vault, 0})
    assert places(new) == {[1, 2, nil], [nil, nil, nil, nil]}
    assert rec(new, 9) == :binary.copy(<<0>>, 50)
    assert Items.get(new, 9) == :free
  end

  test "clear_item keeps a record another place still points at" do
    shared = WizardFixture.field(raw(), 0, 0x120, <<2::little-signed-16>>)
    {:ok, new, _} = Structures.clear_item(shared, 0, {:hero, 0, 1})
    assert places(new) == {[1, nil, nil], [2, nil, nil, nil]}
    assert rec(new, 2) == rec(shared, 2)
  end

  test "clear_item refusals" do
    r = raw()
    assert Structures.clear_item(r, 0, {:hero, 0, 2}) == {:error, :no_item_there}
    assert Structures.clear_item(r, 0, {:vault, 3}) == {:error, :no_item_there}
    assert Structures.clear_item(r, 0, {:hero, 4, 0}) == {:error, :no_such_hero}
    assert Structures.clear_item(r, 6, {:vault, 0}) == {:error, :no_such_wizard}
  end
end
