defmodule Mirror.ItemData do
  @moduledoc """
  The game's premade items, read from `ITEMDATA.LBX` (STORY-056): one entry of 250 records of 56 bytes (a
  `count` and a `record size` of 16 bits each come first). The game draws the artifacts it hands out (a cleared
  lair, a hero's reward) from this table; Mirror offers the same items for a hero's or the vault's places.

  A record is the save's item record (`Mirror.SaveFile.Items`) plus a 6-byte tail that is not decoded (it looks
  like book requirements, and it differs between copies of the file): name (30), icon, slot, type, cost, the eight
  stat bytes, charges, abilities. `number` is the program's "Item #n", the record's position counted from 1.

  **A premade record stores movement as the screen shows it (1 to 4); the save stores half points**, so
  `save_record/1` doubles it (checked on Protection of Ramses, Plate of Enduring Immunity and Shield of Eros:
  4, 2 and 1 here, 8, 4 and 2 in a save).

  Two copies of the file differ in cost and the tail only (51 and about 100 records); the stat bytes agree. The file is
  the player's own copy (`Mirror.GameFiles`); without it `table/0` is `{:error, reason}`.
  """

  alias Mirror.{LBX, Paths}
  alias Mirror.SaveFile.Items

  @record 56

  @type premade :: %{
          number: pos_integer(),
          name: String.t(),
          icon: non_neg_integer(),
          slot: non_neg_integer(),
          slot_name: String.t() | nil,
          type: non_neg_integer(),
          type_name: String.t() | nil,
          cost: non_neg_integer(),
          stats: binary(),
          charges: non_neg_integer(),
          abilities: non_neg_integer()
        }

  @doc "The premade items of an LBX binary, in the file's order."
  @spec parse(binary()) :: {:ok, [premade()]} | {:error, term()}
  def parse(raw) when is_binary(raw) do
    with {:ok, lbx} <- LBX.from_binary(raw),
         {:ok, entry} <- LBX.read_entry(lbx, 0),
         <<count::little-16, @record::little-16, records::binary>> <- entry,
         true <- byte_size(records) >= count * @record do
      items =
        for index <- 0..(count - 1)//1,
            <<name::binary-size(30), icon::little-16, slot, type, cost::little-16,
              stats::binary-size(8), charges::little-16, abilities::little-32,
              _tail::binary-size(6)>> = binary_part(records, index * @record, @record),
            name = name |> :binary.split(<<0>>) |> hd(),
            name != "",
            do: %{
              number: index + 1,
              name: name,
              icon: icon,
              slot: slot,
              slot_name: Items.slot_name(slot),
              type: type,
              type_name: Items.type_name(type),
              cost: cost,
              stats: stats,
              charges: charges,
              abilities: abilities
            }

      {:ok, items}
    else
      {:error, _} = error -> error
      _ -> {:error, :bad_item_table}
    end
  end

  @doc """
  The 50-byte item record a save holds for `premade` (the file's record without its tail, movement in half points).
  """
  @spec save_record(premade()) :: binary()
  def save_record(premade) do
    <<attack, to_hit, defense, movement, rest::binary-size(4)>> = premade.stats
    movement = min(movement * 2, 255)

    String.pad_trailing(premade.name, 30, <<0>>) <>
      <<premade.icon::little-16, premade.slot, premade.type, premade.cost::little-16, attack,
        to_hit, defense, movement>> <>
      rest <> <<premade.charges::little-16, premade.abilities::little-32>>
  end

  @doc """
  The premade table of the game folder (`MIRROR_MOM_PATH`), read once and kept. `{:error, reason}` when the file
  is missing or not an item table; that is not kept, so importing the file takes effect without a restart.
  """
  @spec table() :: {:ok, [premade()]} | {:error, term()}
  def table do
    case :persistent_term.get({__MODULE__, :table}, nil) do
      nil -> load()
      table -> {:ok, table}
    end
  end

  defp load do
    with dir when dir not in [nil, ""] <- Paths.mom_path(),
         file when is_binary(file) <-
           Enum.find(LBX.list_files(dir), &(String.upcase(&1) == "ITEMDATA.LBX")),
         {:ok, raw} <- File.read(Path.join(dir, file)),
         {:ok, table} <- parse(raw) do
      :persistent_term.put({__MODULE__, :table}, table)
      {:ok, table}
    else
      {:error, _} = error -> error
      _ -> {:error, :no_item_table}
    end
  end
end
