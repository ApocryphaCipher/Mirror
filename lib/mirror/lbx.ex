defmodule Mirror.LBX do
  @moduledoc """
  LBX container reader and image decoder.
  """

  require Logger

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

  def open(path) do
    with {:ok, raw} <- File.read(path),
         {:ok, offsets} <- parse_offsets(raw) do
      {:ok, %__MODULE__{path: path, raw: raw, entry_offsets: offsets}}
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

  def entries(%__MODULE__{entry_offsets: offsets, raw: raw}) do
    offsets
    |> Enum.with_index()
    |> Enum.drop(-1)
    |> Enum.map(fn {offset, index} ->
      size = Enum.at(offsets, index + 1) - offset
      %{index: index, offset: offset, size: size, type: entry_type(raw, offset, size)}
    end)
  end

  def read_entry(%__MODULE__{raw: raw, entry_offsets: offsets}, index) do
    with {:ok, {offset, size}} <- entry_slice(offsets, index),
         true <- offset + size <= byte_size(raw) do
      {:ok, binary_part(raw, offset, size)}
    else
      false -> {:error, :entry_out_of_bounds}
      {:error, _} = error -> error
    end
  end

  def decode_image(%__MODULE__{} = lbx, index) do
    decode_image(lbx, index, [])
  end

  def decode_image(%__MODULE__{} = lbx, index, opts) when is_list(opts) do
    palette = Keyword.get(opts, :palette, Palette.default())
    palette_hash = Palette.hash(palette)

    with {:ok, entry} <- read_entry(lbx, index),
         {:ok, image} <- decode_image_data(entry, palette, palette_hash) do
      {:ok, image}
    end
  end

  def decode_palette(%__MODULE__{} = lbx, index) do
    with {:ok, entry} <- read_entry(lbx, index) do
      {:ok, Palette.from_binary(entry)}
    end
  end

  defp parse_offsets(raw) do
    size = byte_size(raw)

    if size < 8 do
      {:error, :short_header}
    else
      <<count32::little-unsigned-integer-size(32), hint::little-unsigned-integer-size(32),
        _::binary>> = raw

      <<count16::little-unsigned-integer-size(16), _::binary>> = raw

      candidates =
        [
          %{count: count32, table: hint},
          %{count: count32, table: 4},
          %{count: count32, table: 8},
          %{count: count16, table: hint},
          %{count: count16, table: 4},
          %{count: count16, table: 8}
        ]
        |> Enum.uniq()

      Enum.find_value(candidates, {:error, :invalid_header}, fn candidate ->
        with {:ok, offsets} <- offsets_from_candidate(raw, candidate),
             true <- offsets_valid?(offsets, size, candidate.table) do
          {:ok, offsets}
        else
          _ -> false
        end
      end)
    end
  end

  defp offsets_from_candidate(raw, %{count: count, table: table}) do
    size = byte_size(raw)

    cond do
      count < 0 ->
        {:error, :invalid_count}

      table < 0 ->
        {:error, :invalid_table}

      table + (count + 1) * 4 > size ->
        {:error, :table_oob}

      true ->
        offsets =
          for i <- 0..count do
            <<_::binary-size(table + i * 4), offset::little-unsigned-integer-size(32), _::binary>> =
              raw

            offset
          end

        {:ok, offsets}
    end
  end

  defp offsets_valid?(offsets, size, table) do
    offsets
    |> Enum.with_index()
    |> Enum.all?(fn {offset, idx} ->
      offset >= 0 and offset <= size and (idx == 0 or offset >= Enum.at(offsets, idx - 1))
    end) and
      Enum.any?(offsets, &(&1 >= table))
  end

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
    entry = binary_part(raw, offset, min(size, 16))

    case entry do
      <<width::little-unsigned-integer-size(16), height::little-unsigned-integer-size(16),
        _frames::little-unsigned-integer-size(16), _flags::little-unsigned-integer-size(16),
        _::binary>>
      when width in 1..1024 and height in 1..1024 ->
        :image

      _ ->
        :binary
    end
  end

  defp decode_image_data(entry, palette, palette_hash) do
    case parse_image_header(entry) do
      {:ok, header} ->
        decode_frames(entry, header, palette, palette_hash)

      :error ->
        decode_raw_image(entry, palette, palette_hash)
    end
  end

  defp parse_image_header(entry) do
    if byte_size(entry) < 8 do
      :error
    else
      <<width::little-unsigned-integer-size(16), height::little-unsigned-integer-size(16),
        frames::little-unsigned-integer-size(16), flags::little-unsigned-integer-size(16),
        rest::binary>> = entry

      cond do
        width < 1 or height < 1 ->
          :error

        width > 1024 or height > 1024 ->
          :error

        frames < 1 or frames > 1024 ->
          :error

        byte_size(rest) < frames * 4 ->
          :error

        true ->
          {:ok, %{width: width, height: height, frames: frames, flags: flags}}
      end
    end
  end

  defp decode_frames(
         entry,
         %{width: width, height: height, frames: frames},
         palette,
         palette_hash
       ) do
    offsets = frame_offsets(entry, frames)
    size = byte_size(entry)

    if offsets == [] do
      decode_raw_image(entry, palette, palette_hash)
    else
      frame_offsets = offsets ++ [size]

      decoded_frames =
        frame_offsets
        |> Enum.with_index()
        |> Enum.drop(-1)
        |> Enum.map(fn {offset, frame_index} ->
          next_offset = Enum.at(frame_offsets, frame_index + 1)
          frame_data = binary_part(entry, offset, max(next_offset - offset, 0))

          case decode_frame(frame_data, width, height) do
            {:ok, indices} ->
              rgba = indices_to_rgba(indices, palette)
              %{index: frame_index, width: width, height: height, rgba: rgba}

            {:error, reason} ->
              Logger.warning("LBX frame decode failed: #{inspect(reason)}")
              %{index: frame_index, width: width, height: height, rgba: empty_rgba(width, height)}
          end
        end)

      primary = List.first(decoded_frames)

      {:ok,
       %Image{
         width: width,
         height: height,
         frame_count: frames,
         frames: decoded_frames,
         rgba: primary && primary.rgba,
         palette_hash: palette_hash
       }}
    end
  end

  defp frame_offsets(entry, frames) do
    data_start = 8 + frames * 4
    size = byte_size(entry)

    offsets =
      for i <- 0..(frames - 1) do
        <<_::binary-size(8 + i * 4), offset::little-unsigned-integer-size(32), _::binary>> = entry

        offset
      end

    if Enum.all?(offsets, &(&1 >= data_start and &1 < size)) and
         Enum.sort(offsets) == offsets do
      offsets
    else
      []
    end
  end

  defp decode_raw_image(entry, palette, palette_hash) do
    size = byte_size(entry)

    if size >= 4 do
      <<width::little-unsigned-integer-size(16), height::little-unsigned-integer-size(16),
        rest::binary>> = entry

      if width > 0 and height > 0 and byte_size(rest) >= width * height do
        indices = binary_part(rest, 0, width * height)
        rgba = indices_to_rgba(indices, palette)

        {:ok,
         %Image{
           width: width,
           height: height,
           frame_count: 1,
           frames: [%{index: 0, width: width, height: height, rgba: rgba}],
           rgba: rgba,
           palette_hash: palette_hash
         }}
      else
        {:error, :unknown_image_format}
      end
    else
      {:error, :unknown_image_format}
    end
  end

  defp decode_frame(data, width, height) do
    case decode_row_rle(data, width, height) do
      {:ok, indices} -> {:ok, indices}
      :error -> decode_raw_frame(data, width, height)
    end
  end

  defp decode_raw_frame(data, width, height) do
    if byte_size(data) >= width * height do
      {:ok, binary_part(data, 0, width * height)}
    else
      {:error, :frame_too_small}
    end
  end

  defp decode_row_rle(data, width, height) do
    cond do
      byte_size(data) < height * 2 ->
        :error

      true ->
        case row_offsets(data, height, 2) do
          {:ok, offsets} ->
            decode_rows_with_offsets(data, offsets, width)

          _ ->
            case row_offsets(data, height, 4) do
              {:ok, offsets} -> decode_rows_with_offsets(data, offsets, width)
              _ -> :error
            end
        end
    end
  end

  defp decode_rows_with_offsets(data, offsets, width) do
    if offsets_valid?(offsets, byte_size(data), 0) do
      offsets = offsets ++ [byte_size(data)]

      rows =
        offsets
        |> Enum.with_index()
        |> Enum.drop(-1)
        |> Enum.map(fn {offset, row_index} ->
          next_offset = Enum.at(offsets, row_index + 1)
          row_data = binary_part(data, offset, max(next_offset - offset, 0))
          decode_row(row_data, width)
        end)

      if Enum.any?(rows, &(&1 == :error)) do
        :error
      else
        {:ok, IO.iodata_to_binary(rows)}
      end
    else
      :error
    end
  end

  defp row_offsets(data, height, size) do
    limit = height * size

    if byte_size(data) < limit do
      {:error, :short_offsets}
    else
      offsets =
        for i <- 0..(height - 1) do
          case size do
            2 ->
              <<_::binary-size(i * 2), offset::little-unsigned-integer-size(16), _::binary>> =
                data

              offset

            4 ->
              <<_::binary-size(i * 4), offset::little-unsigned-integer-size(32), _::binary>> =
                data

              offset
          end
        end

      {:ok, offsets}
    end
  end

  defp decode_row(row_data, width) do
    decode_row(row_data, width, 0, <<>>)
  end

  defp decode_row(_row_data, width, _pixels, acc) when byte_size(acc) >= width do
    binary_part(acc, 0, width)
  end

  defp decode_row(<<>>, width, _pixels, acc) do
    pad = max(width - byte_size(acc), 0)
    <<acc::binary, :binary.copy(<<0>>, pad)::binary>>
  end

  defp decode_row(
         <<skip::unsigned-integer-size(8), count::unsigned-integer-size(8), rest::binary>>,
         width,
         _pixels,
         acc
       ) do
    cond do
      skip == 255 and count == 255 ->
        pad = max(width - byte_size(acc), 0)
        <<acc::binary, :binary.copy(<<0>>, pad)::binary>>

      skip == 0 and count == 0 ->
        pad = max(width - byte_size(acc), 0)
        <<acc::binary, :binary.copy(<<0>>, pad)::binary>>

      byte_size(rest) < count ->
        :error

      true ->
        transparent = :binary.copy(<<0>>, skip)
        <<pixels::binary-size(count), tail::binary>> = rest
        next = <<acc::binary, transparent::binary, pixels::binary>>

        if byte_size(next) >= width do
          binary_part(next, 0, width)
        else
          decode_row(tail, width, byte_size(next), next)
        end
    end
  end

  defp decode_row(_row_data, _width, _pixels, _acc), do: :error

  defp indices_to_rgba(indices, palette) do
    palette_bin = Palette.to_binary(palette)

    for <<idx::unsigned-integer-size(8) <- indices>>, into: <<>> do
      :binary.part(palette_bin, idx * 4, 4)
    end
  end

  defp empty_rgba(width, height) do
    :binary.copy(<<0, 0, 0, 0>>, width * height)
  end
end
