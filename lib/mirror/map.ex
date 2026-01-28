defmodule Mirror.Map do
  @moduledoc """
  Map helpers for tile indexing, layers, and derived computations.
  """

  import Bitwise

  alias Mirror.SaveFile.Blocks

  @width Blocks.map_width()
  @height Blocks.map_height()

  @dirs [
    {0, -1},
    {1, -1},
    {1, 0},
    {1, 1},
    {0, 1},
    {-1, 1},
    {-1, 0},
    {-1, -1}
  ]

  def width, do: @width
  def height, do: @height

  def idx(x, y) when x in 0..(@width - 1) and y in 0..(@height - 1) do
    y * @width + x
  end

  def wrap_x(x) do
    cond do
      x < 0 -> rem(x + @width * 1000, @width)
      x >= @width -> rem(x, @width)
      true -> x
    end
  end

  def clamp_y(y) when y < 0, do: :off
  def clamp_y(y) when y >= @height, do: :off
  def clamp_y(y), do: y

  def get_tile_u8(bin, x, y) do
    index = idx(x, y)
    <<_::binary-size(index), value::unsigned-integer-size(8), _::binary>> = bin
    value
  end

  def get_tile_u16_le(bin, x, y) do
    index = idx(x, y) * 2
    <<_::binary-size(index), value::little-unsigned-integer-size(16), _::binary>> = bin
    value
  end

  def put_tile_u8(bin, x, y, value) do
    index = idx(x, y)
    <<head::binary-size(index), old::unsigned-integer-size(8), tail::binary>> = bin
    {<<head::binary, value::unsigned-integer-size(8), tail::binary>>, old}
  end

  def put_tile_u16_le(bin, x, y, value) do
    index = idx(x, y) * 2
    <<head::binary-size(index), old::little-unsigned-integer-size(16), tail::binary>> = bin
    {<<head::binary, value::little-unsigned-integer-size(16), tail::binary>>, old}
  end

  def apply_changes_u8(bin, changes) do
    Enum.reduce(changes, {bin, []}, fn {x, y, new_value}, {acc, updates} ->
      {updated, old} = put_tile_u8(acc, x, y, new_value)
      {updated, [{x, y, old, new_value} | updates]}
    end)
  end

  def apply_changes_u16(bin, changes) do
    Enum.reduce(changes, {bin, []}, fn {x, y, new_value}, {acc, updates} ->
      {updated, old} = put_tile_u16_le(acc, x, y, new_value)
      {updated, [{x, y, old, new_value} | updates]}
    end)
  end

  def terrain_type(value) when is_integer(value), do: value &&& 0xFF

  def terrain_class(value) do
    water_values = Application.get_env(:mirror, :terrain_water_values, [0])

    if value in water_values do
      :water
    else
      :land
    end
  end

  def computed_adj_mask(terrain_bin) do
    bytes =
      for y <- 0..(@height - 1), x <- 0..(@width - 1) do
        adj_mask(terrain_bin, x, y)
      end

    :erlang.list_to_binary(bytes)
  end

  def adj_mask(terrain_bin, x, y) do
    center = terrain_type(get_tile_u16_le(terrain_bin, x, y))

    Enum.with_index(@dirs)
    |> Enum.reduce(0, fn {{dx, dy}, bit_index}, acc ->
      nx = wrap_x(x + dx)
      ny = clamp_y(y + dy)

      match? =
        case ny do
          :off ->
            false

          _ ->
            neighbor = terrain_type(get_tile_u16_le(terrain_bin, nx, ny))
            neighbor == center
        end

      if match?, do: acc ||| 1 <<< bit_index, else: acc
    end)
  end

  def adj_update_coords(x, y) do
    for dy <- -1..1, dx <- -1..1 do
      nx = wrap_x(x + dx)
      ny = clamp_y(y + dy)

      if ny == :off do
        nil
      else
        {nx, ny}
      end
    end
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end
end
