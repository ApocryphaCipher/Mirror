defmodule Mirror.SaveFile.Heroes do
  @moduledoc """
  A wizard's heroes (STORY-052), read from three places in the save:

    * the wizard record's hero list, `+0x76`: 6 entries of 28 bytes (unit index i16, `-1` for an empty
      slot; the hero's own given name, 14 bytes NUL-padded; 3 item indexes i16, `-1` none; 3 item slot
      types i16),
    * the hero's unit record (`Mirror.SaveFile.Units`: type `+5`, hero slot `+6`, level `+12`,
      experience `+14`, damage `+17`), and
    * the per-player hero table at the start of the file: 6 players x 35 heroes x 12 bytes, indexed by
      the unit type (0 to 34). Of its 12 bytes, `+0` is an i16 that reads -20 for a hero the player has
      hired and 0 otherwise (*guess:* seen only in SAVE2, meaning unknown), `+2` to `+5` are ability bits
      (*not decoded*), `+6` the casting skill and `+7` to `+10` four spell numbers (0 for none). Checked in
      SAVE2: every hero with spells holds numbers inside its own realm's range (Chaos heroes 81 to 120,
      Death heroes 161 to 200).

  See `docs/reference/wizard-heroes-diplomacy-items.md`.
  """

  alias Mirror.SaveFile.UnitTypes

  @wizard_offset 0x9E8
  @wizard_record 0x4C8
  @list_at 0x76
  @entry 28
  @slots 6

  @units_offset 0x00B734
  @unit_record 32
  @units_max 1009
  @count_offset 0x0009E2

  @table_block 420
  @table_entry 12

  @type hero :: %{
          slot: 0..5,
          unit_index: non_neg_integer(),
          name: String.t(),
          type: 0..34,
          type_name: String.t(),
          level: non_neg_integer(),
          experience: integer(),
          damage: non_neg_integer(),
          location:
            %{x: non_neg_integer(), y: non_neg_integer(), plane: :arcanus | :myrror} | nil,
          items: [non_neg_integer()],
          item_places: [non_neg_integer() | nil],
          slot_types: [integer()],
          casting_skill: non_neg_integer(),
          spells: [pos_integer()],
          abilities: non_neg_integer(),
          hired_marker: integer()
        }

  @doc """
  The heroes of wizard `record` (0 to 4), in slot order. A slot that is empty, or whose unit record
  is missing or is not a hero, is left out.
  """
  @spec for_wizard(binary(), non_neg_integer()) :: [hero()]
  def for_wizard(raw, record)
      when is_binary(raw) and record in 0..4//1 and
             byte_size(raw) >= @wizard_offset + (record + 1) * @wizard_record do
    base = @wizard_offset + record * @wizard_record + @list_at

    for slot <- 0..(@slots - 1),
        <<unit::little-signed-16, name::binary-size(14), items::binary-size(6),
          types::binary-size(6)>> =
          binary_part(raw, base + slot * @entry, @entry),
        unit >= 0,
        {:ok, hero} <- [hero(raw, record, slot, unit, name, items, types)],
        do: hero
  end

  def for_wizard(_raw, _record), do: []

  defp hero(raw, record, slot, unit, name, items, types) do
    with true <- unit < @units_max and unit_present?(raw, unit),
         <<x, y, plane, _owner, _moves, type, _hero_slot, _::binary-size(5), level, _,
           experience::little-signed-16, _, damage, _::binary>> <- unit_record(raw, unit),
         true <- type in 0..34//1 and plane in 0..1//1 do
      {:ok,
       %{
         slot: slot,
         unit_index: unit,
         name: name |> :binary.split(<<0>>) |> hd(),
         type: type,
         type_name: UnitTypes.name(type),
         level: level,
         experience: experience,
         damage: damage,
         location: %{x: x, y: y, plane: if(plane == 0, do: :arcanus, else: :myrror)},
         items: for(<<i::little-signed-16 <- items>>, i >= 0, do: i),
         item_places: for(<<i::little-signed-16 <- items>>, do: if(i >= 0, do: i)),
         slot_types: for(<<t::little-signed-16 <- types>>, do: t)
       }
       |> Map.merge(template(raw, record, type))}
    else
      _ -> :error
    end
  end

  defp unit_present?(raw, unit) do
    byte_size(raw) >= @units_offset + (unit + 1) * @unit_record and
      unit < live_count(raw)
  end

  defp live_count(raw) do
    <<_::binary-size(@count_offset), count::little-16, _::binary>> = raw
    count
  end

  defp unit_record(raw, unit), do: binary_part(raw, @units_offset + unit * @unit_record, 32)

  # The per-player table of 35 heroes at the start of the file.
  defp template(raw, record, type) do
    at = record * @table_block + type * @table_entry

    <<marker::little-signed-16, abilities::little-32, skill, spells::binary-size(4), _pad>> =
      binary_part(raw, at, @table_entry)

    %{
      hired_marker: marker,
      abilities: abilities,
      casting_skill: skill,
      spells: for(<<s <- spells>>, s != 0, do: s)
    }
  end
end
