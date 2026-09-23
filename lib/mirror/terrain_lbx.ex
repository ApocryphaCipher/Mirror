defmodule Mirror.TerrainLbx do
  @moduledoc """
  Decode classic `TERRAIN.LBX` into a client tile atlas.

  A save's u16 terrain value is a tile number (0..761 per plane), already
  resolved to the right edge/rotation variant at map generation — so
  rendering is a direct lookup, no classification or smoothing.

  Format (see docs/reference/classic-terrain-format.md):

    * entry 0 — 384-byte tile records addressed from the start of the *file*
      (16-byte header, 20x18 pixels column-major, 8 bytes padding)
    * entry 1 — 2 x 762 u16 pointers: `record = div(lo &&& 0x7F, 3) * 128 + hi`,
      `lo &&& 0x80` = animated (4 consecutive records)
    * entry 2 — 2 x 762 minimap palette indices

  Palette: `FONTS.LBX` entry 2, first 768 bytes (6-bit VGA).
  """

  import Bitwise

  alias Mirror.LBX
  alias Mirror.LBX.Palette

  @tiles_per_plane 762
  @record_size 384
  @record_header 16
  @tile_w 20
  @tile_h 18
  @tile_px @tile_w * @tile_h
  @anim_frames 4

  def tiles_per_plane, do: @tiles_per_plane
  def tile_size, do: {@tile_w, @tile_h}

  @doc "Locate `TERRAIN.LBX` and `FONTS.LBX` (case-insensitive) in `dir` and decode them."
  def load(dir) when dir in [nil, ""], do: {:error, :no_mom_path}

  def load(dir) do
    with {:ok, terrain_path} <- find_file(dir, "TERRAIN.LBX"),
         {:ok, fonts_path} <- find_file(dir, "FONTS.LBX"),
         {:ok, terrain} <- LBX.open(terrain_path),
         {:ok, fonts} <- LBX.open(fonts_path) do
      decode(terrain, fonts)
    end
  end

  @doc false
  def decode(%LBX{} = terrain, %LBX{} = fonts) do
    with {:ok, pointer_bin} <- LBX.read_entry(terrain, 1),
         {:ok, minimap} <- LBX.read_entry(terrain, 2),
         {:ok, font_palette} <- LBX.read_entry(fonts, 2),
         true <-
           byte_size(pointer_bin) >= @tiles_per_plane * 2 * 2 || {:error, :short_pointer_table},
         true <- byte_size(font_palette) >= 768 || {:error, :short_palette} do
      pointers =
        for <<w::little-unsigned-16 <- binary_part(pointer_bin, 0, @tiles_per_plane * 4)>>,
          do: decode_pointer(w)

      {:ok,
       %{
         raw: terrain.raw,
         pointers: pointers,
         minimap: minimap,
         palette: Palette.from_binary(binary_part(font_palette, 0, 768))
       }}
    end
  end

  @doc "Decode an entry-1 pointer word into `{record, frame_count}`."
  def decode_pointer(w) do
    record = div(w &&& 0x7F, 3) * 128 + (w >>> 8)
    frames = if (w &&& 0x80) != 0, do: @anim_frames, else: 1
    {record, frames}
  end

  @doc """
  Raw indexed pixels (row-major, `20*18` bytes) for a file record, or `nil`
  if it lies outside the file.
  """
  def record_pixels(raw, record) do
    offset = record * @record_size + @record_header

    if offset + @tile_px <= byte_size(raw) do
      column_major = binary_part(raw, offset, @tile_px)

      for y <- 0..(@tile_h - 1), x <- 0..(@tile_w - 1), into: <<>> do
        <<:binary.at(column_major, x * @tile_h + y)>>
      end
    end
  end

  @doc """
  Client payload: only the records the pointer table references, packed into
  one indexed pixel blob, plus per-value `[atlas_index, frames]` for each
  plane and the RGBA palette.
  """
  def payload(%{raw: raw, pointers: pointers, minimap: minimap, palette: palette}) do
    records =
      pointers
      |> Enum.flat_map(fn {record, frames} -> Enum.to_list(record..(record + frames - 1)) end)
      |> Enum.uniq()
      |> Enum.filter(&record_pixels(raw, &1))
      |> Enum.sort()

    atlas_index = records |> Enum.with_index() |> Map.new()
    pixels = records |> Enum.map(&record_pixels(raw, &1)) |> IO.iodata_to_binary()

    tiles =
      pointers
      |> Enum.map(fn {record, frames} -> [Map.get(atlas_index, record, -1), frames] end)
      |> Enum.chunk_every(@tiles_per_plane)

    %{
      tile_width: @tile_w,
      tile_height: @tile_h,
      tile_count: length(records),
      pixels: Base.encode64(pixels),
      palette: Base.encode64(Palette.to_binary(palette)),
      tiles: %{arcanus: Enum.at(tiles, 0), myrror: Enum.at(tiles, 1)},
      minimap: %{
        arcanus: :binary.bin_to_list(minimap, 0, @tiles_per_plane),
        myrror: :binary.bin_to_list(minimap, @tiles_per_plane, @tiles_per_plane)
      }
    }
  end

  defp find_file(dir, name) do
    case File.ls(dir) do
      {:ok, files} ->
        case Enum.find(files, &(String.upcase(&1) == name)) do
          nil -> {:error, {:missing, name}}
          file -> {:ok, Path.join(dir, file)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
