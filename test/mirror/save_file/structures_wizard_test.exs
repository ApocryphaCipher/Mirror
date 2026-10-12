defmodule Mirror.SaveFile.StructuresWizardTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.Structures
  alias Mirror.WizardFixture

  @rec 0x9E8
  @size 0x4C8

  defp read(raw, record, at, n), do: binary_part(raw, @rec + record * @size + at, n)

  test "writes gold, mana, fame, books and retorts at their offsets and nothing else" do
    raw = WizardFixture.synthetic()
    retorts = for i <- 0..17, do: i in [1, 17]

    assert {:ok, new, %{changed: [:gold, :mana, :fame, :books, :retorts]}} =
             Structures.edit_wizard(raw, 0,
               gold: 30_000,
               mana: 0,
               fame: 77,
               books: [1, 2, 3, 4, 13],
               retorts: retorts
             )

    assert read(new, 0, 0x356, 2) == <<30_000::little-16>>
    assert read(new, 0, 0x25C, 2) == <<0::little-16>>
    assert read(new, 0, 0x24, 2) == <<77::little-16>>

    assert read(new, 0, 0x5A, 10) ==
             <<1::little-16, 2::little-16, 3::little-16, 4::little-16, 13::little-16>>

    assert read(new, 0, 0x64, 18) ==
             for(on <- retorts, into: <<>>, do: <<if(on, do: 1, else: 0)>>)

    # only those bytes differ; the rival's record is untouched
    assert byte_size(new) == byte_size(raw)
    assert read(new, 1, 0, @size) == read(raw, 1, 0, @size)
  end

  test "the name is written NUL-padded to 20 bytes" do
    {:ok, new, _} = Structures.edit_wizard(WizardFixture.synthetic(), 1, name: "Rjak the Wise")
    assert read(new, 1, 1, 20) == "Rjak the Wise" <> <<0::56>>
    # a shorter name leaves no tail of the old one
    {:ok, shorter, _} = Structures.edit_wizard(new, 1, name: "Al")
    assert read(shorter, 1, 1, 20) == "Al" <> :binary.copy(<<0>>, 18)
  end

  test "refuses bad values, naming the field, and leaves the save alone" do
    raw = WizardFixture.synthetic()

    for {change, reason} <- [
          {[gold: 30_001], :bad_gold},
          {[gold: -1], :bad_gold},
          {[mana: "5"], :bad_mana},
          {[fame: 65_535], :bad_fame},
          {[name: ""], :bad_name},
          {[name: "   "], :bad_name},
          {[name: String.duplicate("x", 20)], :bad_name},
          {[name: "Zoë"], :bad_name},
          {[name: "tab\t"], :bad_name},
          {[books: [1, 2, 3, 4]], :bad_books},
          {[books: [1, 2, 3, 4, 14]], :bad_books},
          {[retorts: [true]], :bad_retorts},
          {[retorts: List.duplicate(1, 18)], :bad_retorts}
        ] do
      assert Structures.edit_wizard(raw, 0, change) == {:error, reason}, inspect(change)
    end

    assert Structures.edit_wizard(raw, 0, colour: 3) == {:error, {:unknown_field, :colour}}
  end

  test "a nameless record, the neutral player and out-of-range records are not wizards" do
    raw = WizardFixture.synthetic()
    assert Structures.edit_wizard(raw, 2, gold: 1) == {:error, :no_such_wizard}
    assert Structures.edit_wizard(raw, 5, gold: 1) == {:error, :no_such_wizard}
    assert Structures.edit_wizard(raw, -1, gold: 1) == {:error, :no_such_wizard}
    assert Structures.edit_wizard(<<1, 2, 3>>, 0, gold: 1) == {:error, :no_such_wizard}
  end
end
