defmodule Mirror.SaveFile.Wizards do
  @moduledoc """
  Wizard records: 6 × `0x4c8` bytes at `0x9e8` (5 wizards, then the neutral
  player). Only the banner colour is read so far: `+0x16`, 0 blue,
  1 green, 2 purple, 3 red, 4 yellow; the neutral record holds 5.
  City and unit `owner` bytes index these records.
  """

  @offset 0x9E8
  @record 0x4C8
  @records 6
  @banner 0x16

  @doc false
  def block_range, do: {@offset, @records * @record}

  @banners %{0 => :blue, 1 => :green, 2 => :purple, 3 => :red, 4 => :yellow}

  @doc "Owner index => banner colour (`:neutral` when not a wizard colour)."
  @spec banners(binary()) :: %{non_neg_integer() => atom()}
  def banners(raw) when byte_size(raw) >= @offset + @records * @record do
    for owner <- 0..(@records - 1), into: %{} do
      banner = :binary.at(raw, @offset + owner * @record + @banner)
      {owner, Map.get(@banners, banner, :neutral)}
    end
  end

  def banners(_raw), do: %{}

  @doc "Owner index => the wizard's name (record `+1`, up to 19 characters); the neutral record has none."
  @spec names(binary()) :: %{non_neg_integer() => String.t()}
  def names(raw) when byte_size(raw) >= @offset + @records * @record do
    for owner <- 0..(@records - 2), into: %{} do
      name =
        raw
        |> binary_part(@offset + owner * @record + 1, 20)
        |> :binary.split(<<0>>)
        |> hd()
        |> :unicode.characters_to_binary(:latin1)

      {owner, name}
    end
  end

  def names(_raw), do: %{}
end
