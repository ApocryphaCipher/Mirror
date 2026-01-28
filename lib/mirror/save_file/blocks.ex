defmodule Mirror.SaveFile.Blocks do
  @moduledoc """
  Offsets and sizes for Classic save map blocks.

  Offsets are configurable via application config or environment variables.
  See config/runtime.exs for the environment variable names.
  """

  @map_width 60
  @map_height 40

  @u8_plane_size @map_width * @map_height
  @u16_plane_size @map_width * @map_height * 2

  @layers [
    :terrain,
    :terrain_flags,
    :minerals,
    :exploration,
    :landmass
  ]

  @layer_sizes %{
    terrain: @u16_plane_size,
    terrain_flags: @u8_plane_size,
    minerals: @u8_plane_size,
    exploration: @u8_plane_size,
    landmass: @u8_plane_size
  }

  def layers, do: @layers

  def map_width, do: @map_width
  def map_height, do: @map_height

  def layer_size(layer), do: Map.fetch!(@layer_sizes, layer)

  def layer_offset(layer) do
    offsets = Application.get_env(:mirror, __MODULE__, %{})
    Map.get(offsets, layer)
  end

  def plane_slice_offset(layer, plane_index) when plane_index in [0, 1] do
    case layer_offset(layer) do
      nil -> {:error, {:missing_offset, layer}}
      base -> {:ok, base + plane_index * layer_size(layer)}
    end
  end

  def slice_plane(binary, layer, plane_index) do
    with {:ok, offset} <- plane_slice_offset(layer, plane_index) do
      size = layer_size(layer)

      if byte_size(binary) < offset + size do
        {:error, {:short_binary, layer}}
      else
        <<_::binary-size(offset), slice::binary-size(size), _::binary>> = binary
        {:ok, slice}
      end
    end
  end

  def put_plane_slice(binary, layer, plane_index, slice) do
    with {:ok, offset} <- plane_slice_offset(layer, plane_index) do
      size = layer_size(layer)

      if byte_size(slice) != size do
        {:error, {:slice_size_mismatch, layer}}
      else
        <<head::binary-size(offset), _::binary-size(size), tail::binary>> = binary
        {:ok, <<head::binary, slice::binary, tail::binary>>}
      end
    end
  end
end
