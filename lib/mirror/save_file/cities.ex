defmodule Mirror.SaveFile.Cities do
  @moduledoc """
  The cities block of a classic save: up to 100 records of 114 bytes at
  `0x8aac`, the live count a u16 at `0x9e0`.

  Record layout, per momedit's `City.cs` and the Save Game Format wiki
  (see docs/reference/momedit-source/), checked against SAVE1.GAM's 27
  cities (readable names, coordinates on the map, owners 0–5):

    * `+0`  name, NUL-terminated (14 bytes)
    * `+14` race
    * `+15` x, `+16` y (tiles), `+17` plane (0 Arcanus, 1 Myrror)
    * `+18` owner: wizard record 0–4, or 5 for the neutral cities
    * `+19` size class: 0 Outpost, 1 Hamlet, 2 Village, from the game's
      city-screen titles (STORY-032); higher classes not seen in-game yet
    * `+20` population (thousands)
    * `+31`..`+66` buildings, one byte per building id 0–35: 1 built,
      0xFF not built, 0 replaced by a better building. City Walls (id 35)
      is `+66`: building it in-game changed exactly that byte
      (STORY-032). Ids from ReMoM, checked in-game for 26 Marketplace,
      29 Granary and 35 City Walls (docs/reference/live-ram-map.md).
    * `+67`..`+92` city enchantments, one byte per slot: 0 none, else the
      caster's player index + 1. Slot order from ReMoM; checked by casting
      Nature's Eye (slot 14) and by editing a save (famine, Nature Ward,
      Stream of Life, Gaia's Blessing, Inspirations, Prosperity), see
      docs/reference/surveyor-formula.md.
    * `+101`..`+113` road links: a bit per city index (bit `i % 8` of byte
      `i / 8`), set for each city joined to this one by road. Checked
      through the Surveyor's road trade bonus (surveyor-formula.md).
  """

  @offset 0x8AAC
  @record 114
  @max 100
  @count_offset 0x9E0

  @doc false
  def block_range, do: {@offset, @max * @record}
  @doc false
  def count_offset, do: @count_offset

  @built 1
  @replaced 0
  @walls 35

  @enchantments ~w(wall_of_fire chaos_rift dark_rituals evil_presence cursed_lands
                   pestilence cloud_of_shadow famine flying_fortress nature_ward
                   sorcery_ward chaos_ward life_ward death_ward natures_eye earth_gate
                   stream_of_life gaias_blessing inspirations prosperity astral_gate
                   heavenly_light consecration wall_of_darkness altar_of_battle
                   nightshade)a

  @size_names %{0 => "Outpost", 1 => "Hamlet", 2 => "Village"}

  # Race ids (`+14`), in the game's order. Checked against the game's own city
  # screens and saves: Lizardmen (10, a city Kevin changed to Lizardmen), Halfling
  # (6, Hialanth's screen), Dwarf (4, Fire Keep and Raug Wall).
  @race_names [
    "Barbarian",
    "Beastmen",
    "Dark Elf",
    "Draconian",
    "Dwarf",
    "Gnoll",
    "Halfling",
    "High Elf",
    "High Men",
    "Klackon",
    "Lizardman",
    "Nomad",
    "Orc",
    "Troll"
  ]

  # Building ids, the byte `+31 + id` of a city record. 26 Marketplace, 29 Granary and
  # 35 City Walls were checked in the game (STORY-032); the rest follow the same order,
  # which is kazzmir's building list shifted by two (his list has no Trade Goods and
  # Housing at the front), and match what Kevin's cities have built.
  @building_names %{
    1 => "Trade Goods",
    2 => "Housing",
    3 => "Barracks",
    4 => "Armory",
    5 => "Fighters' Guild",
    6 => "Armorers' Guild",
    7 => "War College",
    8 => "Smithy",
    9 => "Stables",
    10 => "Animists' Guild",
    11 => "Fantastic Stable",
    12 => "Shipwrights' Guild",
    13 => "Ship Yard",
    14 => "Maritime Guild",
    15 => "Sawmill",
    16 => "Library",
    17 => "Sages' Guild",
    18 => "Oracle",
    19 => "Alchemists' Guild",
    20 => "University",
    21 => "Wizards' Guild",
    22 => "Shrine",
    23 => "Temple",
    24 => "Parthenon",
    25 => "Cathedral",
    26 => "Marketplace",
    27 => "Bank",
    28 => "Merchants' Guild",
    29 => "Granary",
    30 => "Farmers' Market",
    31 => "Foresters' Guild",
    32 => "Builders' Hall",
    33 => "Mechanicians' Guild",
    34 => "Miners' Guild",
    35 => "City Walls"
  }

  @type city :: %{
          index: non_neg_integer(),
          name: String.t(),
          race: non_neg_integer(),
          x: non_neg_integer(),
          y: non_neg_integer(),
          plane: :arcanus | :myrror,
          owner: non_neg_integer(),
          size: non_neg_integer(),
          population: non_neg_integer(),
          walled: boolean(),
          buildings: %{non_neg_integer() => :built | :replaced},
          enchantments: %{atom() => non_neg_integer()},
          road_links: [non_neg_integer()]
        }

  @doc "The live cities in a save's raw bytes."
  @spec parse(binary()) :: {:ok, [city()]} | {:error, term()}
  def parse(<<_::binary-size(@count_offset), count::little-16, _::binary>> = raw)
      when count <= @max and byte_size(raw) >= @offset + count * @record do
    cities =
      for index <- 0..(count - 1)//1,
          city = record(binary_part(raw, @offset + index * @record, @record), index),
          do: city

    {:ok, cities}
  end

  def parse(_raw), do: {:error, :no_cities_block}

  defp record(
         <<name::binary-size(14), race, x, y, plane, owner, size, population, _::binary-size(10),
           buildings::binary-size(36), enchantments::binary-size(26), _::binary-size(8),
           road_links::binary-size(13)>>,
         index
       )
       when x < 60 and y < 40 and plane in [0, 1] do
    buildings = buildings(buildings)

    %{
      index: index,
      name: city_name(name),
      race: race,
      x: x,
      y: y,
      plane: if(plane == 0, do: :arcanus, else: :myrror),
      owner: owner,
      size: size,
      population: population,
      walled: buildings[@walls] == :built,
      buildings: buildings,
      enchantments: enchantments(enchantments),
      road_links: road_links(road_links)
    }
  end

  defp record(_bytes, _index), do: nil

  # The game's names are single-byte text; reading them as Latin-1 keeps any
  # high byte valid UTF-8 (LiveView sends names as JSON).
  @doc false
  def city_name(raw) do
    raw |> :binary.split(<<0>>) |> hd() |> :unicode.characters_to_binary(:latin1) |> String.trim()
  end

  # Building id 0 is "no building"; its byte is always 0.
  defp buildings(<<_none, statuses::binary>>) do
    for {status, id} <- Enum.with_index(:binary.bin_to_list(statuses), 1),
        status in [@built, @replaced],
        into: %{},
        do: {id, if(status == @built, do: :built, else: :replaced)}
  end

  defp enchantments(slots) do
    for {caster, name} <- Enum.zip(:binary.bin_to_list(slots), @enchantments),
        caster != 0,
        into: %{},
        do: {name, caster - 1}
  end

  defp road_links(bits) do
    for {byte, i} <- Enum.with_index(:binary.bin_to_list(bits)),
        bit <- 0..7,
        Bitwise.band(byte, Bitwise.bsl(1, bit)) != 0,
        do: i * 8 + bit
  end

  @doc """
  The game's name for a size class, or `"size N"` for classes not yet seen
  in-game.
  """
  @spec size_name(non_neg_integer()) :: String.t()
  def size_name(size), do: Map.get(@size_names, size, "size #{size}")

  # What each building replaces (BUILDDAT.LBX, the game's own table, read 2026-10-11; its entry
  # index is the save's building id, which confirms the ids above): building => the building it
  # replaces. The game marks the replaced one `0` ("replaced") instead of removing it.
  @replaces %{
    4 => 3,
    6 => 5,
    7 => 6,
    11 => 9,
    13 => 12,
    14 => 13,
    20 => 16,
    21 => 19,
    23 => 22,
    24 => 23,
    25 => 24,
    27 => 26,
    28 => 27,
    30 => 29
  }

  # What a building needs first, as building ids (BUILDDAT.LBX). The game enforces this only
  # when a player builds: neutral cities in saves have Shrines without a Builders Hall, so the
  # editor treats it as a hint. Terrain needs (forest for a Sawmill, water for a Shipwrights'
  # Guild, minerals for a Miners' Guild) are not listed.
  @requires %{
    4 => [8, 3],
    5 => [4],
    6 => [5],
    7 => [20, 6],
    9 => [8],
    10 => [23, 9],
    11 => [6, 10],
    13 => [15, 12],
    14 => [4, 13],
    16 => [32],
    17 => [16],
    18 => [24, 20],
    19 => [17],
    20 => [17],
    21 => [19, 20],
    22 => [32],
    23 => [22],
    24 => [23],
    25 => [24],
    26 => [8],
    27 => [26, 20],
    28 => [13, 27],
    29 => [32],
    30 => [29, 26],
    31 => [15],
    33 => [34, 20],
    34 => [32],
    35 => [32]
  }

  @doc "The building ids a city can have (3 to 35; 1 and 2 are production items)."
  def building_ids, do: Enum.to_list(3..35)

  @doc "The id of the building `id` replaces, or `nil`."
  def building_replaces(id), do: Map.get(@replaces, id)

  @doc "The building ids `id` needs first (a hint; see the table's note)."
  def building_requires(id), do: Map.get(@requires, id, [])

  @doc "The race's name, or `\"race N\"` for an id outside the game's 14."
  @spec race_name(non_neg_integer()) :: String.t()
  def race_name(race), do: Enum.at(@race_names, race) || "race #{race}"

  @doc "The building's name, or `\"building N\"`."
  @spec building_name(non_neg_integer()) :: String.t()
  def building_name(id), do: Map.get(@building_names, id, "building #{id}")

  @doc "The city enchantment slots' names, in slot order."
  def enchantment_names, do: @enchantments
end
