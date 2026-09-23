defmodule Mirror.LBX.Palette do
  @moduledoc """
  Palette utilities for LBX image decoding.
  """

  @type rgba_tuple :: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}

  def default do
    for i <- 0..255 do
      {i, i, i, 255}
    end
  end

  def from_binary(bin) when is_binary(bin) do
    case byte_size(bin) do
      768 -> from_rgb_triplets(bin, 63)
      1024 -> from_rgba_quads(bin)
      _ -> default()
    end
  end

  @doc """
  The game's shared palette from 768 bytes of 6-bit VGA RGB (`FONTS.LBX`
  entry 2), with index 0 transparent as the game draws it.
  """
  def game(bin) when byte_size(bin) == 768 do
    [{r, g, b, _} | rest] = from_rgb_triplets(bin, 63)
    [{r, g, b, 0} | rest]
  end

  @doc "Overwrite colours `first..` with a 6-bit RGB patch (an image's embedded palette)."
  def patch(palette, {first, bin}) do
    colours = from_rgb_triplets(bin, 63)

    palette
    |> Enum.with_index()
    |> Enum.map(fn {colour, i} ->
      if i >= first and i < first + length(colours), do: Enum.at(colours, i - first), else: colour
    end)
  end

  def to_binary(palette) when is_list(palette) do
    Enum.reduce(palette, <<>>, fn {r, g, b, a}, acc ->
      <<acc::binary, r::unsigned-integer-size(8), g::unsigned-integer-size(8),
        b::unsigned-integer-size(8), a::unsigned-integer-size(8)>>
    end)
  end

  def hash(palette) when is_list(palette) do
    data = to_binary(palette)

    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end

  defp from_rgb_triplets(bin, max_value) do
    scale = if max_value == 0, do: 1, else: 255 / max_value

    bin
    |> :binary.bin_to_list()
    |> Enum.chunk_every(3)
    |> Enum.map(fn [r, g, b] ->
      {
        clamp_color(round(r * scale)),
        clamp_color(round(g * scale)),
        clamp_color(round(b * scale)),
        255
      }
    end)
  end

  defp from_rgba_quads(bin) do
    bin
    |> :binary.bin_to_list()
    |> Enum.chunk_every(4)
    |> Enum.map(fn [r, g, b, a] ->
      {r, g, b, a}
    end)
  end

  defp clamp_color(value) when value < 0, do: 0
  defp clamp_color(value) when value > 255, do: 255
  defp clamp_color(value), do: value
end
