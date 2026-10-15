defmodule Mirror.WizardFixture do
  @moduledoc "A synthetic save with two wizards (no game data), for the wizard page and edit tests."

  @offset 0x9E8
  @record 0x4C8

  def put(raw, at, bytes) do
    size = byte_size(bytes)
    <<head::binary-size(^at), _::binary-size(^size), tail::binary>> = raw
    head <> bytes <> tail
  end

  def field(raw, record, at, bytes), do: put(raw, @offset + record * @record + at, bytes)

  # A zeroed save with Jafar (record 0, blue) and a rival (record 1, red).
  def synthetic do
    # Unused node records are 0xFF, as in the game (a zeroed one is a node owned by wizard 0).
    raw = put(:binary.copy(<<0>>, 123_300), 0x6058, :binary.copy(<<0xFF>>, 30 * 48))

    # Both wizards' fortresses are active (x, y, plane, active); an inactive one is a banished wizard.
    raw
    |> put(0x65F8, <<7, 17, 0, 1, 23, 25, 0, 1>>)
    |> field(0, 0x00, <<7>>)
    |> field(0, 0x01, String.pad_trailing("Jafar", 20, <<0>>))
    |> field(0, 0x16, <<0>>)
    |> field(0, 0x24, <<10::little-16, 12::little-16>>)
    |> field(0, 0x2A, <<34, 33, 33>>)
    |> field(0, 0x34, <<19::little-16, 3::little-16, 53::little-16>>)
    |> field(0, 0x2E, <<38::little-16, 21::little-16, 1::little-16>>)
    |> field(0, 0x54, <<5::little-16, 60::little-16, 2::little-16>>)
    |> field(0, 0x5A, <<0::little-16, 12::little-16, 0::little-16, 3::little-16, 0::little-16>>)
    |> field(0, 0x64 + 0, <<1>>)
    |> field(0, 0x64 + 13, <<1>>)
    |> field(
      0,
      0x25A,
      <<383::little-16, 500::little-16, 2500::little-16, 0::little-16, 19::little-16>>
    )
    |> field(0, 0x264, <<2, 1, 1>>)
    |> field(0, 0x264 + 40, <<2>>)
    |> field(0, 0x356, <<1234::little-16>>)
    |> field(0, 0x128, <<0, 1, 0, 0, 0, 0>>)
    |> field(0, 0x128 + 42, <<0, 25, 0, 0, 0, -81::signed>>)
    |> field(0, 0x128 + 48, <<0, 1, 0, 0, 0, 3>>)
    |> field(0, 0x482 + 3, <<1>>)
    |> field(0, 0x482 + 18, <<1>>)
    |> field(1, 0x128, <<1, 0, 0, 0, 0, 0>>)
    |> field(1, 0x128 + 42, <<-20::signed, 0, 0, 0, 0, 0>>)
    |> field(1, 0x01, String.pad_trailing("Sharee", 20, <<0>>))
    |> field(1, 0x16, <<3>>)
  end

  @doc """
  Gives Jafar (record 0) one hero in slot 0: unit 1, type 31, named "Harold", level 2, 27 xp, damage 3, at
  7,17 Arcanus. The other five slots are empty (-1), as the game writes them.
  """
  def with_hero(raw, items \\ [-1, -1, -1]) do
    entry =
      <<1::little-signed-16>> <>
        String.pad_trailing("Harold", 14, <<0>>) <>
        for(i <- items, into: <<>>, do: <<i::little-signed-16>>) <>
        <<1::little-16, 5::little-16, 6::little-16>>

    empty = <<-1::little-signed-16>> <> :binary.copy(<<0>>, 26)

    unit =
      <<7, 17, 0, 0, 2, 31, 0, 0, 0, 0, 0, 0, 2, 0, 27::little-16, 0, 3>> <>
        :binary.copy(<<0>>, 14)

    raw
    |> field(0, 0x76, entry <> :binary.copy(empty, 5))
    |> put(0x9E2, <<2::little-16>>)
    |> put(0x00B734 + 32, unit)
  end

  @doc """
  Writes item records into the item block (`index => {name, type, slot, cost, stats, spell, charges, abilities}`,
  stats being the eight stat bytes) and gives wizard `record`'s vault the item indexes `vault` (padded with -1).
  """
  def with_items(raw, items, record \\ 0, vault \\ []) do
    raw =
      Enum.reduce(items, raw, fn {index, {name, type, slot, cost, stats, charges, abilities}},
                                 acc ->
        put(
          acc,
          0x6FB8 + index * 50,
          String.pad_trailing(name, 30, <<0>>) <>
            <<0::little-16, slot, type, cost::little-16>> <>
            :binary.list_to_bin(stats) <> <<charges::little-16, abilities::little-32>>
        )
      end)

    places = Enum.take(vault ++ [-1, -1, -1, -1], 4)
    field(raw, record, 0x120, for(i <- places, into: <<>>, do: <<i::little-signed-16>>))
  end

  def put_bytes(raw, at, bytes), do: put(raw, at, bytes)

  @doc "Marks wizard `record`'s fortress inactive: the game then treats him as banished."
  def banish(raw, record), do: put(raw, 0x65F8 + record * 4 + 3, <<0>>)
end
