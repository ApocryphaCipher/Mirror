defmodule MirrorWeb.ItemPanel do
  @moduledoc """
  An item (`Mirror.SaveFile.Items`) in words for the pages (STORY-055): name, type, cost, the stat bonuses,
  the special powers and the charged spell. Pure; the pages draw it.

  The special powers come from the game's `ITEMPOW.LBX` (`Mirror.ItemPowers`) and the spell name from
  `Mirror.Spells`; without those files the item still shows its stats, and a non-zero ability mask is flagged as
  `unnamed_powers` instead of being named.
  """

  alias Mirror.{ItemPowers, Spells}

  @type described :: %{
          index: non_neg_integer(),
          name: String.t(),
          kind: String.t(),
          cost: non_neg_integer(),
          stats: [String.t()],
          powers: [String.t()],
          unnamed_powers: boolean(),
          spell: String.t() | nil
        }

  @doc """
  Describes `item`. `powers` is `ItemPowers.table/0`'s list or `nil`, `spell_table` is `Spells.table/0`'s map or `nil`.
  """
  @spec describe(map(), [map()] | nil, map() | nil) :: described()
  def describe(item, powers, spell_table) do
    %{
      index: item.index,
      name: item.name,
      kind: kind(item),
      cost: item.cost,
      stats: stats(item),
      powers: if(is_list(powers), do: ItemPowers.names_for(powers, item.abilities), else: []),
      unnamed_powers: item.abilities != 0 and not is_list(powers),
      spell: spell(item, spell_table)
    }
  end

  defp kind(%{type_name: nil, slot_name: nil}), do: "item"
  defp kind(%{type_name: nil, slot_name: slot}), do: slot
  defp kind(%{type_name: type}), do: type

  # The stat bytes are the plain numbers on the Create Artifact screen; the spell save byte is shown as a penalty
  # there ("-1 Spell Save" is the byte 1). **Movement is stored in half points in a save** (*inferred*, 2026-10-15:
  # Protection of Ramses, Plate of Enduring Immunity and Shield of Eros have 8, 4 and 2 in SAVE2 against 4, 2 and 1 in
  # the premade table, all their other bytes equal), so it is shown halved.
  defp stats(item) do
    for {label, value, sign} <- [
          {"Attack", item.attack, "+"},
          {"To Hit", item.to_hit, "+"},
          {"Defense", item.defense, "+"},
          {"Movement", item.movement / 2, "+"},
          {"Resistance", item.resistance, "+"},
          {"Spell Skill", item.spell_skill, "+"},
          {"Spell Save", item.spell_save, "-"}
        ],
        value > 0,
        do: "#{sign}#{number(value)} #{label}"
  end

  defp number(value) when is_float(value) do
    if value == Float.floor(value),
      do: Integer.to_string(trunc(value)),
      else: Float.to_string(value)
  end

  defp number(value), do: Integer.to_string(value)

  defp spell(%{spell: 0}, _table), do: nil

  defp spell(%{spell: number, charges: charges}, table) do
    name = Spells.name(table, number)
    if charges > 0, do: "#{name} ×#{charges}", else: name
  end
end
