defmodule Mirror.SaveFile.Items do
  @moduledoc """
  The save's item block (STORY-054): 138 records of 50 bytes at `0x6FB8`, right after the encounters and
  right before the cities. Every item index in the save is a position in it: a hero's three
  (`Mirror.SaveFile.Heroes`), a wizard's four vault items (`+0x120` of the wizard record, see `vault/2`)
  and a lair's (`Mirror.SaveFile.Encounters`).

  A record (`docs/reference/wizard-heroes-diplomacy-items.md`):

    * `+0` name, 30 bytes NUL-padded
    * `+30` icon (u16, a picture in `ITEMS.LBX`)
    * `+32` slot, `+33` type: the codes are the Create Artifact screen's, checked on 14 premade items
    * `+34` cost (u16)
    * `+36..+43` attack, to hit, defense, movement, resistance, spell skill, spell save, spell (8 x u8);
      the spell is the 1-based number of the charged spell, `charges` how many
    * `+44` charges (u16)
    * `+46` abilities, a u32 mask: the OR of the powers' masks in the game's `ITEMPOW.LBX`

  A record with an empty name is a free slot. Names of the powers are not read here: they are in
  `ITEMPOW.LBX`, which is not in `Mirror.GameFiles.manifest/0`, so `abilities` stays a mask.
  """

  @offset 0x6FB8
  @record 50
  @count 138

  @wizard_offset 0x9E8
  @wizard_record 0x4C8
  @vault_at 0x120

  @types ~w(Sword Mace Axe Bow Staff Wand Misc Shield Chain Plate)

  @type item :: %{
          index: 0..137,
          name: String.t(),
          icon: non_neg_integer(),
          slot: non_neg_integer(),
          slot_name: String.t() | nil,
          type: non_neg_integer(),
          type_name: String.t() | nil,
          cost: non_neg_integer(),
          attack: non_neg_integer(),
          to_hit: non_neg_integer(),
          defense: non_neg_integer(),
          movement: non_neg_integer(),
          resistance: non_neg_integer(),
          spell_skill: non_neg_integer(),
          spell_save: non_neg_integer(),
          spell: non_neg_integer(),
          charges: non_neg_integer(),
          abilities: non_neg_integer()
        }

  @doc false
  def block_range, do: {@offset, @count * @record}

  @doc "How many item slots a save has."
  def count, do: @count

  @doc """
  The items in use (a slot with a name), in index order, or `{:error, :no_items_block}` when the
  save is too short to hold the block.
  """
  @spec parse(binary()) :: {:ok, [item()]} | {:error, :no_items_block}
  def parse(raw) when is_binary(raw) and byte_size(raw) >= @offset + @count * @record do
    items =
      for index <- 0..(@count - 1),
          {:ok, item} <- [decode(binary_part(raw, @offset + index * @record, @record), index)],
          do: item

    {:ok, items}
  end

  def parse(_raw), do: {:error, :no_items_block}

  @doc "The item at `index`, `:free` for an empty slot, or `:error` for an index outside 0..137."
  @spec get(binary(), integer()) :: {:ok, item()} | :free | :error
  def get(raw, index)
      when is_binary(raw) and index in 0..(@count - 1)//1 and
             byte_size(raw) >= @offset + @count * @record do
    case decode(binary_part(raw, @offset + index * @record, @record), index) do
      {:ok, item} -> {:ok, item}
      :free -> :free
    end
  end

  def get(_raw, _index), do: :error

  @doc """
  The items for a list of item indexes (a hero's, a vault's, a lair's), in the list's order. An index
  that is out of range or a free slot is left out.
  """
  @spec for_indexes(binary(), [integer()]) :: [item()]
  def for_indexes(raw, indexes) when is_list(indexes) do
    for index <- indexes, {:ok, item} <- [get(raw, index)], do: item
  end

  @doc """
  The item indexes in the vault of wizard `record` (0 to 4): four i16 at `+0x120`, `-1` for an empty place.
  Checked in SAVE2: Jafar's vault holds item 2, "Protection of Ramses".
  """
  @spec vault(binary(), non_neg_integer()) :: [non_neg_integer()]
  def vault(raw, record)
      when is_binary(raw) and record in 0..4//1 and
             byte_size(raw) >= @wizard_offset + (record + 1) * @wizard_record do
    at = @wizard_offset + record * @wizard_record + @vault_at
    for <<i::little-signed-16 <- binary_part(raw, at, 8)>>, i >= 0, do: i
  end

  def vault(_raw, _record), do: []

  @doc """
  The four places of wizard `record`'s vault in order, an item index or `nil` for an empty place (`-1` in the save).
  Moving an item needs the place, not just the list: `vault/2` leaves the empty ones out.
  """
  @spec vault_places(binary(), non_neg_integer()) :: [non_neg_integer() | nil]
  def vault_places(raw, record)
      when is_binary(raw) and record in 0..4//1 and
             byte_size(raw) >= @wizard_offset + (record + 1) * @wizard_record do
    at = @wizard_offset + record * @wizard_record + @vault_at
    for <<i::little-signed-16 <- binary_part(raw, at, 8)>>, do: if(i >= 0, do: i)
  end

  def vault_places(_raw, _record), do: []

  @doc "The Create Artifact screen's type name for a type code (0 Sword to 9 Plate), or `nil`."
  @spec type_name(integer()) :: String.t() | nil
  def type_name(type) when type in 0..9//1, do: Enum.at(@types, type)
  def type_name(_type), do: nil

  @doc "What a slot code means: 1 melee weapon, 2 bow, 4 staff or wand, 5 armor or shield, 6 misc; `nil` otherwise."
  @spec slot_name(integer()) :: String.t() | nil
  def slot_name(1), do: "melee weapon"
  def slot_name(2), do: "bow"
  def slot_name(3), do: "any weapon"
  def slot_name(4), do: "staff or wand"
  def slot_name(5), do: "armor"
  def slot_name(6), do: "misc"
  def slot_name(_), do: nil

  @doc """
  Whether an item whose slot code is `item_slot` fits a hero's place of slot type `place_type`: the same code, or any
  of the three weapon kinds (1 melee, 2 bow, 4 staff or wand) in an "any weapon" place (type 3, Warrax's, Mystic X's and
  Reywind's first place; Warrax's is (3, 5, 6) in SAVE2, the weapon kinds are from kazzmir's `AnyWeapon`).
  """
  @spec slot_accepts?(integer(), integer()) :: boolean()
  def slot_accepts?(place_type, item_slot),
    do: place_type == item_slot or (place_type == 3 and item_slot in [1, 2, 4])

  defp decode(<<name::binary-size(30), rest::binary>>, index) do
    <<icon::little-16, slot, type, cost::little-16, attack, to_hit, defense, movement, resistance,
      spell_skill, spell_save, spell, charges::little-16, abilities::little-32>> = rest

    name = name |> :binary.split(<<0>>) |> hd()

    if name == "" do
      :free
    else
      {:ok,
       %{
         index: index,
         name: name,
         icon: icon,
         slot: slot,
         slot_name: slot_name(slot),
         type: type,
         type_name: type_name(type),
         cost: cost,
         attack: attack,
         to_hit: to_hit,
         defense: defense,
         movement: movement,
         resistance: resistance,
         spell_skill: spell_skill,
         spell_save: spell_save,
         spell: spell,
         charges: charges,
         abilities: abilities
       }}
    end
  end
end
