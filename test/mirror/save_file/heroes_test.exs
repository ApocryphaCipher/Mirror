defmodule Mirror.SaveFile.HeroesTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.Heroes
  alias Mirror.WizardFixture

  @units 0x00B734

  # Jafar (record 0) has hero slot 0 = unit 1, a type-31 hero ("Sir Harold") named "Harold", level 2, 27 xp,
  # one item, with a Chaos-style template: hired marker -20, casting skill 5, spells 86, 88, 94.
  defp with_hero(raw) do
    entry =
      <<1::little-signed-16>> <>
        String.pad_trailing("Harold", 14, <<0>>) <>
        <<1::little-signed-16, -1::little-signed-16, -1::little-signed-16>> <>
        <<1::little-16, 5::little-16, 6::little-16>>

    unit =
      <<7, 17, 0, 0, 2, 31, 0, 0, 0, 0, 0, 0, 2, 0, 27::little-16>> <>
        :binary.copy(<<0>>, 32 - 16)

    # the game marks an empty slot with unit index -1
    empty = <<-1::little-signed-16>> <> :binary.copy(<<0>>, 26)

    raw
    |> WizardFixture.field(0, 0x76, entry <> :binary.copy(empty, 5))
    |> WizardFixture.put_bytes(0x9E2, <<2::little-16>>)
    |> WizardFixture.put_bytes(@units + 32, unit)
    |> WizardFixture.put_bytes(
      0 * 420 + 31 * 12,
      <<-20::little-signed-16, 0x12, 0x12, 0x00, 0x20, 5, 86, 88, 94, 0, 0>>
    )
  end

  test "reads a hero from the list, its unit record and the per-player table" do
    assert [hero] = Heroes.for_wizard(with_hero(WizardFixture.synthetic()), 0)

    assert %{
             slot: 0,
             unit_index: 1,
             name: "Harold",
             type: 31,
             level: 2,
             experience: 27,
             location: %{x: 7, y: 17, plane: :arcanus},
             items: [1],
             casting_skill: 5,
             spells: [86, 88, 94],
             hired_marker: -20,
             abilities: 0x20001212
           } = hero

    assert is_binary(hero.type_name)
  end

  test "an empty list, another wizard, a dead or non-hero unit and a short save give no heroes" do
    raw = WizardFixture.synthetic()
    assert Heroes.for_wizard(raw, 0) == []

    # another wizard's list is empty (-1 in every slot, as the game writes it)
    empty = <<-1::little-signed-16>> <> :binary.copy(<<0>>, 26)
    other = WizardFixture.field(with_hero(raw), 1, 0x76, :binary.copy(empty, 6))
    assert Heroes.for_wizard(other, 1) == []

    # the unit is beyond the live count
    assert Heroes.for_wizard(WizardFixture.put_bytes(with_hero(raw), 0x9E2, <<1::little-16>>), 0) ==
             []

    # the unit is not a hero (type 50)
    not_hero = WizardFixture.put_bytes(with_hero(raw), @units + 32 + 5, <<50>>)
    assert Heroes.for_wizard(not_hero, 0) == []

    assert Heroes.for_wizard(<<0, 1, 2>>, 0) == []
    assert Heroes.for_wizard(raw, 5) == []
  end
end
