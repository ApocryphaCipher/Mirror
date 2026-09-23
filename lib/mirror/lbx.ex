defmodule Mirror.LBX do
  @moduledoc """
  LBX container reader and image decoder for classic Master of Magic files.

  Container: `u16 count`, `u16 0xFEAD`, 4 bytes, then `count + 1` u32 entry
  offsets from byte 8. Most files also carry a name table at `0x200`: one
  32-byte row per entry, a 9-byte NUL-padded name (`SITES`) then a
  NUL-terminated description (`blue`). See `names/1`.

  Image entries (see docs/reference/overland-sprites-and-save-blocks.md):

    * header: `u16 width, height, 0, frames, delay, ?, ?, palette_info, flags`,
      then `frames + 1` u32 frame offsets at `0x12`
    * each frame starts with a byte: `1` = fresh frame, `0` = drawn over the
      previous frame (animation deltas)
    * then one record per column, left to right: `0xFF` = empty column, else
      a mode byte (`0x00` copy, `0x80` RLE), a size byte, and `size` bytes of
      runs: `count, skip` then `count` encoded bytes starting `skip` rows
      below the previous run. In RLE mode a byte `> 0xDF` repeats the next
      byte `b - 0xDF` times.
    * `palette_info` (when non-zero) points at `u16 offset, first, count`: a
      6-bit RGB patch over colours `first..first+count-1`.

  Colours come from the game palette (`FONTS.LBX` entry 2, see
  `game_palette/1`), where index 0 is transparent.
  """

  alias Mirror.LBX.{Image, Palette}

  defstruct [
    :path,
    :raw,
    :entry_offsets
  ]

  @type t :: %__MODULE__{
          path: String.t(),
          raw: binary(),
          entry_offsets: [non_neg_integer()]
        }

  @name_table 0x200
  @name_row 32
  @frame_table 0x12

  def open(path) do
    with {:ok, raw} <- File.read(path),
         {:ok, lbx} <- from_binary(raw) do
      {:ok, %{lbx | path: path}}
    end
  end

  @doc "Parse an LBX already in memory (no path, so no game palette lookup)."
  def from_binary(raw) when is_binary(raw) do
    with {:ok, offsets} <- parse_offsets(raw) do
      {:ok, %__MODULE__{raw: raw, entry_offsets: offsets}}
    end
  end

  def list_files(dir) do
    case dir do
      nil -> []
      "" -> []
      path -> path |> File.ls!() |> Enum.filter(&String.ends_with?(String.upcase(&1), ".LBX"))
    end
  rescue
    _ -> []
  end

  def entries(%__MODULE__{entry_offsets: offsets, raw: raw} = lbx) do
    names = names(lbx)

    offsets
    |> Enum.with_index()
    |> Enum.drop(-1)
    |> Enum.map(fn {offset, index} ->
      size = Enum.at(offsets, index + 1) - offset
      label = Enum.at(names, index)

      %{
        index: index,
        offset: offset,
        size: size,
        type: entry_type(raw, offset, size),
        name: label && label.name,
        description: label && label.description
      }
    end)
  end

  @doc """
  The name table at `0x200`: one `%{name, description}` per entry, or `nil`
  where the file has no (readable) row for it. Files without a table (the
  sound banks, `TERRAIN.LBX`) give all `nil`s.
  """
  def names(%__MODULE__{raw: raw, entry_offsets: [first | _] = offsets}) do
    count = length(offsets) - 1
    rows_fit = max(div(first - @name_table, @name_row), 0)

    for index <- 0..(count - 1)//1 do
      if index < rows_fit, do: name_row(raw, @name_table + index * @name_row)
    end
  end

  def names(_lbx), do: []

  def read_entry(%__MODULE__{raw: raw, entry_offsets: offsets}, index) do
    with {:ok, {offset, size}} <- entry_slice(offsets, index),
         true <- offset + size <= byte_size(raw) do
      {:ok, binary_part(raw, offset, size)}
    else
      false -> {:error, :entry_out_of_bounds}
      {:error, _} = error -> error
    end
  end

  @doc """
  Decode an image entry. `palette:` is `:auto` (the game palette from the
  file's own directory, patched by the entry's embedded colours),
  `:grayscale` (raw indices as grey levels), or an explicit palette list.
  """
  def decode_image(%__MODULE__{} = lbx, index, opts \\ []) when is_list(opts) do
    with {:ok, entry} <- read_entry(lbx, index),
         {:ok, header} <- parse_image_header(entry),
         {:ok, palette, _source} <- resolve_palette(lbx, index, opts),
         {:ok, frames} <- decode_frames(entry, header) do
      palette_hash = Palette.hash(palette)

      frames =
        Enum.map(frames, fn {frame_index, indices} ->
          %{
            index: frame_index,
            width: header.width,
            height: header.height,
            indices: indices,
            rgba: indices_to_rgba(indices, palette)
          }
        end)

      {:ok,
       %Image{
         width: header.width,
         height: header.height,
         frame_count: header.frames,
         frames: frames,
         rgba: frames |> List.first() |> Map.get(:rgba),
         palette_hash: palette_hash
       }}
    else
      :error -> {:error, :not_an_image}
      error -> error
    end
  end

  @doc """
  The palette `decode_image/3` would use, and where it came from:
  `:game`, `:game_embedded` (game palette + this entry's patch),
  `:grayscale`, `:explicit`, or `:explicit_embedded`.
  """
  def resolve_palette(%__MODULE__{} = lbx, index, opts \\ []) when is_list(opts) do
    with {:ok, entry} <- read_entry(lbx, index) do
      {base, source} =
        case Keyword.get(opts, :palette, :auto) do
          palette when is_list(palette) ->
            {palette, :explicit}

          :grayscale ->
            {Palette.default(), :grayscale}

          _auto ->
            case game_palette(lbx.path && Path.dirname(lbx.path)) do
              {:ok, palette} -> {palette, :game}
              {:error, _} -> {Palette.default(), :grayscale}
            end
        end

      case {source, embedded_palette(entry)} do
        {:grayscale, _} -> {:ok, base, source}
        {_, nil} -> {:ok, base, source}
        {_, patch} -> {:ok, Palette.patch(base, patch), :"#{source}_embedded"}
      end
    end
  end

  def decode_palette(%__MODULE__{} = lbx, index) do
    with {:ok, entry} <- read_entry(lbx, index) do
      {:ok, Palette.from_binary(entry)}
    end
  end

  @doc """
  The game's shared palette: first 768 bytes of `FONTS.LBX` entry 2 in `dir`
  (6-bit VGA), with index 0 transparent.
  """
  def game_palette(dir) when dir in [nil, ""], do: {:error, :no_mom_path}

  def game_palette(dir) do
    with {:ok, name} <- find_file(dir, "FONTS.LBX"),
         {:ok, fonts} <- open(Path.join(dir, name)),
         {:ok, entry} <- read_entry(fonts, 2),
         true <- byte_size(entry) >= 768 || {:error, :short_palette} do
      {:ok, Palette.game(binary_part(entry, 0, 768))}
    end
  end

  defp find_file(dir, name) do
    case Enum.find(list_files(dir), &(String.upcase(&1) == name)) do
      nil -> {:error, {:missing, name}}
      found -> {:ok, found}
    end
  end

  defp name_row(raw, offset) do
    <<name::binary-size(9), description::binary-size(23)>> = binary_part(raw, offset, @name_row)
    name = cstring(name)
    description = cstring(description)

    if name != "" and printable?(name) and printable?(description),
      do: %{name: name, description: description}
  end

  defp cstring(bin), do: bin |> :binary.split(<<0>>) |> hd()
  defp printable?(bin), do: for(<<c <- bin>>, reduce: true, do: (acc -> acc and c in 32..126))

  # `u16 count`, `u16 0xFEAD`, 4 bytes, then `count + 1` u32 offsets at 8.
  defp parse_offsets(
         <<count::little-16, 0xFEAD::little-16, _::binary-size(4), rest::binary>> = raw
       )
       when byte_size(rest) >= (count + 1) * 4 do
    offsets = for <<offset::little-32 <- binary_part(rest, 0, (count + 1) * 4)>>, do: offset

    if offsets == Enum.sort(offsets) and List.last(offsets) <= byte_size(raw),
      do: {:ok, offsets},
      else: {:error, :invalid_offsets}
  end

  defp parse_offsets(_raw), do: {:error, :invalid_header}

  defp entry_slice(offsets, index) do
    count = length(offsets) - 1

    cond do
      index < 0 or index >= count ->
        {:error, :invalid_index}

      true ->
        offset = Enum.at(offsets, index)
        size = Enum.at(offsets, index + 1) - offset

        if size < 0 do
          {:error, :invalid_offsets}
        else
          {:ok, {offset, size}}
        end
    end
  end

  defp entry_type(raw, offset, size) do
    case parse_image_header(binary_part(raw, offset, size)) do
      {:ok, _} -> :image
      :error -> :binary
    end
  end

  defp parse_image_header(
         <<width::little-16, height::little-16, 0::little-16, frames::little-16,
           _delay::little-16, _::binary-size(4), palette_info::little-16, _flags::little-16,
           _::binary>> = entry
       )
       when width in 1..320 and height in 1..200 and frames in 1..256 do
    table_end = @frame_table + (frames + 1) * 4

    with true <- byte_size(entry) >= table_end,
         offsets = frame_offsets(entry, frames),
         true <- offsets == Enum.sort(offsets),
         true <- hd(offsets) >= table_end and List.last(offsets) <= byte_size(entry) do
      {:ok,
       %{
         width: width,
         height: height,
         frames: frames,
         offsets: offsets,
         palette_info: palette_info
       }}
    else
      _ -> :error
    end
  end

  defp parse_image_header(_entry), do: :error

  defp frame_offsets(entry, frames) do
    for <<offset::little-32 <- binary_part(entry, @frame_table, (frames + 1) * 4)>>, do: offset
  end

  defp decode_frames(entry, %{width: width, height: height, offsets: offsets}) do
    blank = List.duplicate(:binary.copy(<<0>>, height), width)

    offsets
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], blank}, fn {[from, to], index}, {:ok, acc, previous} ->
      frame = binary_part(entry, from, to - from)

      case decode_frame(frame, width, height, previous, blank) do
        {:ok, columns} ->
          {:cont, {:ok, [{index, columns_to_rows(columns, height)} | acc], columns}}

        {:error, reason} ->
          {:halt, {:error, {:frame, index, reason}}}
      end
    end)
    |> case do
      {:ok, frames, _last} -> {:ok, Enum.reverse(frames)}
      error -> error
    end
  end

  # A frame starting with 0 is a delta over the previous frame; anything
  # else starts from a transparent canvas.
  defp decode_frame(<<0, rest::binary>>, width, height, previous, _blank),
    do: decode_columns(rest, width, height, previous, [])

  defp decode_frame(<<_, rest::binary>>, width, height, _previous, blank),
    do: decode_columns(rest, width, height, blank, [])

  defp decode_frame(<<>>, _width, _height, _previous, _blank), do: {:error, :empty_frame}

  defp decode_columns(_data, 0, _height, _base, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_columns(<<0xFF, rest::binary>>, width, height, [base | bases], acc),
    do: decode_columns(rest, width - 1, height, bases, [base | acc])

  defp decode_columns(
         <<mode, size, runs::binary-size(size), rest::binary>>,
         width,
         height,
         [base | bases],
         acc
       )
       when mode in [0x00, 0x80] do
    case decode_runs(runs, mode == 0x80, height, base, 0, []) do
      {:ok, column} -> decode_columns(rest, width - 1, height, bases, [column | acc])
      error -> error
    end
  end

  defp decode_columns(_data, _width, _height, _bases, _acc), do: {:error, :bad_column}

  # Builds one column: untouched rows come from `base`, runs overwrite.
  defp decode_runs(<<>>, _rle?, height, base, y, acc) do
    {:ok, IO.iodata_to_binary(Enum.reverse([binary_part(base, y, height - y) | acc]))}
  end

  defp decode_runs(
         <<count, skip, data::binary-size(count), rest::binary>>,
         rle?,
         height,
         base,
         y,
         acc
       ) do
    start = y + skip
    pixels = if rle?, do: expand_rle(data, []), else: data
    stop = start + byte_size(pixels)

    if stop > height do
      {:error, :column_overflow}
    else
      acc = [pixels, binary_part(base, y, skip) | acc]
      decode_runs(rest, rle?, height, base, stop, acc)
    end
  end

  defp decode_runs(_runs, _rle?, _height, _base, _y, _acc), do: {:error, :bad_run}

  defp expand_rle(<<>>, acc), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp expand_rle(<<repeat, value, rest::binary>>, acc) when repeat > 0xDF,
    do: expand_rle(rest, [:binary.copy(<<value>>, repeat - 0xDF) | acc])

  defp expand_rle(<<value, rest::binary>>, acc), do: expand_rle(rest, [value | acc])

  defp columns_to_rows(columns, height) do
    columns = List.to_tuple(columns)
    width = tuple_size(columns)

    for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
      <<:binary.at(elem(columns, x), y)>>
    end
  end

  defp embedded_palette(entry) do
    with {:ok, %{palette_info: info}} when info > 0 <- parse_image_header(entry),
         <<_::binary-size(^info), offset::little-16, first::little-16, count::little-16,
           _::binary>> <- entry,
         true <- first + count <= 256 and offset + count * 3 <= byte_size(entry) do
      {first, binary_part(entry, offset, count * 3)}
    else
      _ -> nil
    end
  end

  defp indices_to_rgba(indices, palette) do
    lookup = palette |> Palette.to_binary()

    for <<idx <- indices>>, into: <<>> do
      binary_part(lookup, idx * 4, 4)
    end
  end
end
