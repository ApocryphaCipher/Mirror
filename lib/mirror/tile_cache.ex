defmodule Mirror.TileCache do
  @moduledoc """
  Cache decoded LBX frames on disk for fast startup.
  """

  require Logger

  alias Mirror.LBX
  alias Mirror.LBX.{Image, Palette}
  alias Mirror.Paths

  @decoder_version 3

  def fetch(%LBX{} = lbx, index, opts \\ []) do
    palette_opt = Keyword.get(opts, :palette, :auto)

    {palette, _source} =
      case LBX.resolve_palette(lbx, index, palette: palette_opt) do
        {:ok, palette, source} -> {palette, source}
        {:error, _} -> {Palette.default(), :fallback}
      end

    palette_hash = Palette.hash(palette)
    entry_dir = entry_dir(lbx.path, index)
    meta_path = meta_path(entry_dir, palette_hash)

    with true <- File.exists?(meta_path),
         {:ok, meta} <- read_meta(meta_path),
         {:ok, frames} <- read_frames(entry_dir, meta, palette_hash) do
      {:ok,
       %Image{
         width: meta.width,
         height: meta.height,
         frame_count: meta.frame_count,
         frames: frames,
         rgba: frames |> List.first() |> then(&(&1 && &1.rgba)),
         palette_hash: palette_hash
       }}
    else
      _ ->
        decode_and_store(lbx, index, palette, palette_hash, entry_dir, meta_path)
    end
  end

  def key(lbx_path, index, frame, palette_hash) do
    basename = Path.basename(lbx_path)
    "#{basename}|#{index}|#{frame}|#{palette_hash}|v#{@decoder_version}"
  end

  defp decode_and_store(lbx, index, palette, palette_hash, entry_dir, meta_path) do
    with {:ok, image} <- LBX.decode_image(lbx, index, palette: palette),
         :ok <- write_cache(entry_dir, meta_path, image, palette_hash) do
      {:ok, image}
    end
  end

  defp entry_dir(lbx_path, index) do
    cache_dir = Paths.tile_cache_dir() || default_cache_dir()
    basename = Path.basename(lbx_path, Path.extname(lbx_path))
    Path.join([cache_dir, basename, "entry-#{index}"])
  end

  defp default_cache_dir do
    Path.expand("../../priv/tile_cache", __DIR__)
  end

  defp meta_path(entry_dir, palette_hash) do
    Path.join(entry_dir, "meta-#{@decoder_version}-#{palette_hash}.json")
  end

  defp frame_path(entry_dir, frame_index, palette_hash) do
    Path.join(entry_dir, "frame-#{frame_index}-#{@decoder_version}-#{palette_hash}.rgba")
  end

  defp write_cache(entry_dir, meta_path, %Image{} = image, palette_hash) do
    with :ok <- File.mkdir_p(entry_dir),
         :ok <- write_frames(entry_dir, image.frames, palette_hash),
         :ok <- write_meta(meta_path, image, palette_hash) do
      :ok
    end
  end

  defp write_frames(entry_dir, frames, palette_hash) do
    Enum.reduce_while(frames, :ok, fn frame, :ok ->
      path = frame_path(entry_dir, frame.index, palette_hash)

      case File.write(path, frame.rgba) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp write_meta(meta_path, %Image{} = image, palette_hash) do
    meta = %{
      "version" => @decoder_version,
      "palette_hash" => palette_hash,
      "width" => image.width,
      "height" => image.height,
      "frame_count" => image.frame_count,
      "frames" =>
        Enum.map(image.frames, fn frame ->
          %{
            "index" => frame.index,
            "width" => frame.width,
            "height" => frame.height
          }
        end)
    }

    File.write(meta_path, Jason.encode!(meta, pretty: true))
  end

  defp read_meta(path) do
    with {:ok, raw} <- File.read(path),
         {:ok, meta} <- Jason.decode(raw) do
      {:ok,
       %{
         width: meta["width"],
         height: meta["height"],
         frame_count: meta["frame_count"],
         frames: meta["frames"] || [],
         palette_hash: meta["palette_hash"]
       }}
    else
      {:error, reason} ->
        Logger.warning("Failed to read tile cache meta: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp read_frames(entry_dir, meta, palette_hash) do
    Enum.reduce_while(meta.frames, {:ok, []}, fn frame, {:ok, acc} ->
      path = frame_path(entry_dir, frame["index"], palette_hash)

      case File.read(path) do
        {:ok, rgba} ->
          {:cont,
           {:ok,
            acc ++
              [
                %{
                  index: frame["index"],
                  width: frame["width"],
                  height: frame["height"],
                  rgba: rgba
                }
              ]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end
end
