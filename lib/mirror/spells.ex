defmodule Mirror.Spells do
  @moduledoc """
  The game's spell table, read from `SPELLDAT.LBX` (STORY-049).

  Entry 0 holds 215 records of 36 bytes (a `count` and a `record size` of 16 bits each come first).
  The spell **number** is the record index, 0 being "None": 1 to 40 Nature, 41 to 80 Sorcery, 81 to 120 Chaos,
  121 to 160 Life, 161 to 200 Death, 201 to 214 Arcane, the same numbering the wizard's spell library uses
  (byte *n* - 1 of the library is spell *n*).

  A record: `+0` name (18 bytes, NUL-padded), `+23` realm (0 Nature, 1 Sorcery, 2 Chaos, 3 Life, 4 Death,
  5 Arcane), `+26` casting cost (u16), `+28` research cost (u16). *Checked against the game's own
  figures (2026-10-12):* Earth Lore costs 30 and takes 250 research points, Raise Volcano 200 and 680; the realm byte agrees with
  the numbering for every spell (`docs/reference/wizard-record-and-exploration.md`). The other bytes are not decoded.

  The file is the player's own copy (`Mirror.GameFiles`); without it `table/0` is `{:error, reason}` and the wizard page shows
  numbers instead of names.
  """

  alias Mirror.{LBX, Paths}

  @record 36
  @realms [:nature, :sorcery, :chaos, :life, :death, :arcane]

  @type spell :: %{
          number: pos_integer(),
          name: String.t(),
          realm: atom(),
          cost: non_neg_integer(),
          research: non_neg_integer()
        }

  @doc "The realm names in the order of the realm byte."
  def realms, do: @realms

  @doc "The spells (numbers 1 to 214) of an LBX binary, as a map of number to spell."
  @spec parse(binary()) :: {:ok, %{pos_integer() => spell()}} | {:error, term()}
  def parse(raw) when is_binary(raw) do
    with {:ok, lbx} <- LBX.from_binary(raw),
         {:ok, entry} <- LBX.read_entry(lbx, 0),
         <<count::little-16, @record::little-16, records::binary>> <- entry,
         true <- byte_size(records) >= count * @record do
      spells =
        for number <- 1..(count - 1)//1, into: %{} do
          <<_::binary-size(^number * @record), name::binary-size(18), _::binary-size(5), realm,
            _::binary-size(2), cost::little-16, research::little-16, _::binary>> = records

          {number,
           %{
             number: number,
             name: name |> :binary.split(<<0>>) |> hd(),
             realm: Enum.at(@realms, realm, :arcane),
             cost: cost,
             research: research
           }}
        end

      {:ok, spells}
    else
      {:error, _} = error -> error
      _ -> {:error, :bad_spell_table}
    end
  end

  @doc """
  The spell table of the game folder (`MIRROR_MOM_PATH`), read once and kept. `{:error, reason}` when the file is
  missing or not a spell table; that is not kept, so importing the file takes effect without a restart.
  """
  @spec table() :: {:ok, %{pos_integer() => spell()}} | {:error, term()}
  def table do
    case :persistent_term.get({__MODULE__, :table}, nil) do
      nil -> load()
      table -> {:ok, table}
    end
  end

  defp load do
    with dir when dir not in [nil, ""] <- Paths.mom_path(),
         {:ok, file} <- find(dir),
         {:ok, raw} <- File.read(Path.join(dir, file)),
         {:ok, table} <- parse(raw) do
      :persistent_term.put({__MODULE__, :table}, table)
      {:ok, table}
    else
      {:error, _} = error -> error
      _ -> {:error, :no_spell_table}
    end
  end

  # The file's name differs in case between installs (`Spelldat.lbx`, `SPELLDAT.LBX`).
  defp find(dir) do
    case Enum.find(LBX.list_files(dir), &(String.upcase(&1) == "SPELLDAT.LBX")) do
      nil -> {:error, :no_spell_table}
      file -> {:ok, file}
    end
  end

  @doc "The name for a spell number: the game's, or `Spell N` when the table is not available."
  @spec name(%{pos_integer() => spell()} | nil, integer()) :: String.t()
  def name(table, number) when is_map(table) do
    case Map.get(table, number) do
      %{name: name} -> name
      _ -> "Spell #{number}"
    end
  end

  def name(_table, number), do: "Spell #{number}"
end
