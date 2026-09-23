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
end
