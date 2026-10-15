defmodule Mirror.ItemPowers do
  @moduledoc """
  The game's item powers, read from `ITEMPOW.LBX` (STORY-054): one entry of 67 records of 30 bytes
  (a `count` and a `record size` of 16 bits each come first). A record: `+0` name (22 bytes, NUL-padded),
  `+22` kind, `+23` realm (0 Nature, 1 Sorcery, 2 Chaos, 3 Life, 4 Death), `+24` amount, `+25` a pad and
  `+26` a u32 ability mask.

  The **special powers** (Flaming, Haste, Regeneration ...) are the records with a non-zero mask: an item's `abilities`
  (`Mirror.SaveFile.Items`) is the OR of its powers' masks, so `names_for/2` lists the powers whose bit is set. The
  **stat powers** ("+3 Defense") have a zero mask: they are the item's stat bytes, not bits. Checked on 14 premade
  items against `ITEMMAKE.EXE` (docs/reference/wizard-heroes-diplomacy-items.md). *Not decoded:* the meaning of `kind`
  beyond what the names show (0 attack, 1 to hit, 2 defense, 3 spell skill, 4 spell save, 5 movement, 6 resistance, 7 to 9 the
  special powers).

  Two copies of the file differ in five stat records (the community patch rebalances items); the masks and names
  agree. The file is the player's own copy (`Mirror.GameFiles`); without it `table/0` is `{:error, reason}`.
  """

  alias Mirror.{LBX, Paths}

  @record 30

  @type power :: %{
          index: non_neg_integer(),
          name: String.t(),
          kind: non_neg_integer(),
          realm: non_neg_integer(),
          amount: non_neg_integer(),
          mask: non_neg_integer()
        }

  @doc "The powers (index 0 up) of an LBX binary; an empty record at the end is left out."
  @spec parse(binary()) :: {:ok, [power()]} | {:error, term()}
  def parse(raw) when is_binary(raw) do
    with {:ok, lbx} <- LBX.from_binary(raw),
         {:ok, entry} <- LBX.read_entry(lbx, 0),
         <<count::little-16, @record::little-16, records::binary>> <- entry,
         true <- byte_size(records) >= count * @record do
      powers =
        for index <- 0..(count - 1)//1,
            <<name::binary-size(22), kind, realm, amount, _pad, mask::little-32>> =
              binary_part(records, index * @record, @record),
            name = name |> :binary.split(<<0>>) |> hd(),
            name != "",
            do: %{index: index, name: name, kind: kind, realm: realm, amount: amount, mask: mask}

      {:ok, powers}
    else
      {:error, _} = error -> error
      _ -> {:error, :bad_power_table}
    end
  end

  @doc """
  The names of the special powers whose bit is set in an item's ability `mask`, in the table's order.
  Bits that no power owns are ignored.
  """
  @spec names_for([power()], non_neg_integer()) :: [String.t()]
  def names_for(powers, mask) when is_list(powers) and is_integer(mask) do
    for %{mask: bit, name: name} <- powers, bit != 0, Bitwise.band(bit, mask) == bit, do: name
  end

  @doc """
  The power table of the game folder (`MIRROR_MOM_PATH`), read once and kept. `{:error, reason}` when the file is
  missing or not a power table; that is not kept, so importing the file takes effect without a restart.
  """
  @spec table() :: {:ok, [power()]} | {:error, term()}
  def table do
    case :persistent_term.get({__MODULE__, :table}, nil) do
      nil -> load()
      table -> {:ok, table}
    end
  end

  defp load do
    with dir when dir not in [nil, ""] <- Paths.mom_path(),
         file when is_binary(file) <-
           Enum.find(LBX.list_files(dir), &(String.upcase(&1) == "ITEMPOW.LBX")),
         {:ok, raw} <- File.read(Path.join(dir, file)),
         {:ok, table} <- parse(raw) do
      :persistent_term.put({__MODULE__, :table}, table)
      {:ok, table}
    else
      {:error, _} = error -> error
      _ -> {:error, :no_power_table}
    end
  end
end
