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
      name: name |> :binary.split(<<0>>) |> hd() |> String.trim(),
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
end
