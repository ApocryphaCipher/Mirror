defmodule Mirror.SaveFile.Encounters do
  @moduledoc """
  The encounter zones of a save in full (STORY-020): towers' guards, node guardians and the
  lairs, caves, temples, ruins and keeps. 102 records of 24 bytes at `0x6628` (the layout is
  in docs/reference/kazzmir-save-layouts.md, "Encounter zones").

  `Mirror.SaveFile.Sites` reads only what the Surveyor needs; this reads every field the lair
  panel shows. Nothing here writes: `Mirror.SaveFile.Structures.edit_encounter/3` does.

  Per record: `+0` x, `+1` y, `+2` plane, `+3` intact (1 = not cleared), `+4` kind, then two
  guard slots (`+5` type, `+6` count byte; `+7` type, `+8` count byte), `+9` unknown,
  `+10` gold and `+12` mana (i16), `+14` a spell-reward code (0 to 6 in every save; what the
  codes mean is not decoded), `+15` flags (who has looked at it: not decoded), `+16` the item
  count and `+18`, `+20`, `+22` three item ids (i16). A guard's count byte holds two nibbles: the low
  one is the guards left, the high one the starting count (checked in the game,
  live-ram-map.md). An empty guard slot is type 0, count 0 in all 247 empty slots seen.
  """

  @offset 0x6628
  @records 102
  @size 24

  @kind_names %{
    0 => "Tower of Wizardry",
    1 => "Chaos node guardians",
    2 => "Nature node guardians",
    3 => "Sorcery node guardians",
    4 => "Cave",
    5 => "Dungeon",
    6 => "Ancient temple",
    7 => "Abandoned keep",
    8 => "Monster lair",
    9 => "Ruins",
    10 => "Fallen temple"
  }

  @type guard :: %{
          slot: 1 | 2,
          type: non_neg_integer(),
          left: non_neg_integer(),
          start: non_neg_integer()
        }

  @doc "The kind's name (0 tower, 1 to 3 node guardians, 4 to 10 the sites)."
  @spec kind_name(integer()) :: String.t()
  def kind_name(kind), do: Map.get(@kind_names, kind, "site #{kind}")

  @doc "True for the kinds that are a site of their own (cave to fallen temple)."
  def lair_kind?(kind), do: kind in 4..10

  @doc "Every live record (not all zeros, on the map), with its real index."
  @spec all(binary()) :: [map()]
  def all(raw) when is_binary(raw) and byte_size(raw) >= @offset + @records * @size do
    for index <- 0..(@records - 1),
        record = decode(index, binary_part(raw, @offset + index * @size, @size)),
        record != nil,
        do: record
  end

  def all(_raw), do: []

  @doc "The record with this index, or `nil`."
  @spec get(binary(), non_neg_integer()) :: map() | nil
  def get(raw, index), do: Enum.find(all(raw), &(&1.index == index))

  @doc "The records standing on `{x, y, plane}`; a tower stands on both planes, so it matches either."
  @spec at(binary(), {integer(), integer(), 0 | 1}) :: [map()]
  def at(raw, {x, y, plane}) do
    for e <- all(raw), {e.x, e.y} == {x, y}, e.plane == plane, do: e
  end

  defp decode(_index, <<0::size(192)>>), do: nil

  defp decode(
         index,
         <<x, y, plane, intact, kind, g1, c1, g2, c2, unknown9, gold::little-signed-16,
           mana::little-signed-16, spell, flags, item_count, unknown17, i1::little-signed-16,
           i2::little-signed-16, i3::little-signed-16>>
       )
       when x < 60 and y < 40 and plane in [0, 1] do
    %{
      index: index,
      x: x,
      y: y,
      plane: plane,
      intact: intact == 1,
      kind: kind,
      guards: guards([{1, g1, c1}, {2, g2, c2}]),
      gold: gold,
      mana: mana,
      spell_code: spell,
      flags: flags,
      item_count: item_count,
      items: Enum.take([i1, i2, i3], max(0, min(item_count, 3))),
      unknown9: unknown9,
      unknown17: unknown17
    }
  end

  defp decode(_index, _bytes), do: nil

  # A slot with a zero count byte is empty.
  defp guards(slots) do
    for {slot, type, count} <- slots, count != 0 do
      %{slot: slot, type: type, left: Bitwise.band(count, 0x0F), start: Bitwise.bsr(count, 4)}
    end
  end
end
