defmodule Mirror.TileAtlas do
  @moduledoc """
  Build tile atlas data from asset mappings and cached LBX frames.
  """

  require Logger

  alias Mirror.{AssetMap, MomimePngIndex, Paths, TileCache}
  alias Mirror.LBX

  def build(opts \\ []) do
    case MomimePngIndex.load_assets() do
      {:ok, assets} ->
        assets

      :error ->
        palette = Keyword.get(opts, :palette, :auto)
        terrain_map = AssetMap.load(:terrain)
        overlay_map = AssetMap.load(:overlay)
        mom_path = Paths.mom_path()

        {images, terrain_groups} =
          if map_size(terrain_map) == 0 do
            fallback_terrain_groups(mom_path, palette, %{})
          else
            build_groups(terrain_map, mom_path, palette, %{})
          end

        {images, overlay_groups} = build_groups(overlay_map, mom_path, palette, images)

        %{
          backend: :lbx,
          images: images,
          terrain_groups: terrain_groups,
          overlay_groups: overlay_groups,
          momime: nil
        }
    end
  end

  defp build_groups(map, mom_path, palette, images) when is_map(map) do
    Enum.reduce(map, {images, %{}}, fn {group, entries}, {images_acc, groups_acc} ->
      {images_acc, entry_list} =
        build_group_entries(group, entries, mom_path, palette, images_acc)

      {images_acc, Map.put(groups_acc, group, entry_list)}
    end)
  end

  defp build_group_entries(_group, entries, mom_path, palette, images) do
    normalized = normalize_entries(entries)

    Enum.reduce(normalized, {images, []}, fn entry, {images_acc, list_acc} ->
      case load_entry(entry, mom_path, palette, images_acc) do
        {:ok, {images_next, tile_entry}} ->
          {images_next, list_acc ++ [tile_entry]}

        {:error, reason} ->
          Logger.debug("Skipping tile entry: #{inspect(reason)}")
          {images_acc, list_acc}
      end
    end)
  end

  defp normalize_entries(entries) when is_list(entries) do
    Enum.map(entries, &normalize_entry/1)
  end

  defp normalize_entries(entries) when is_map(entries) do
    Enum.flat_map(entries, fn {variant, list} ->
      list
      |> List.wrap()
      |> Enum.map(fn entry ->
        entry
        |> normalize_entry()
        |> Map.put_new("variant", variant)
      end)
    end)
  end

  defp normalize_entries(_), do: []

  defp normalize_entry(entry) when is_map(entry), do: entry
  defp normalize_entry(_), do: %{}

  defp load_entry(entry, mom_path, palette, images) do
    with lbx_name when is_binary(lbx_name) <- Map.get(entry, "lbx"),
         index when is_integer(index) <- parse_int(Map.get(entry, "index")),
         path <- resolve_lbx_path(lbx_name, mom_path),
         {:ok, lbx} <- LBX.open(path),
         {:ok, image} <- TileCache.fetch(lbx, index, palette: palette) do
      frame_index = parse_int(Map.get(entry, "frame")) || 0
      frame = Enum.find(image.frames, &(&1.index == frame_index)) || List.first(image.frames)

      if frame do
        key = TileCache.key(path, index, frame.index, image.palette_hash)
        images = Map.put_new(images, key, encode_image(frame))

        {:ok,
         {images,
          %{
            "key" => key,
            "width" => frame.width,
            "height" => frame.height,
            "variant" => Map.get(entry, "variant")
          }}}
      else
        {:error, :missing_frame}
      end
    else
      _ -> {:error, :invalid_entry}
    end
  end

  defp resolve_lbx_path(name, mom_path) do
    cond do
      Path.type(name) == :absolute ->
        name

      mom_path in [nil, ""] ->
        name

      true ->
        Path.join(mom_path, name)
    end
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_int(_), do: nil

  defp encode_image(frame) do
    %{
      "width" => frame.width,
      "height" => frame.height,
      "rgba" => Base.encode64(frame.rgba)
    }
  end

  defp fallback_terrain_groups(nil, _palette, images), do: {images, %{}}
  defp fallback_terrain_groups("", _palette, images), do: {images, %{}}

  defp fallback_terrain_groups(mom_path, palette, images) do
    lbx_files = LBX.list_files(mom_path)
    default_name = find_default_lbx(lbx_files)

    case open_default_lbx(mom_path, default_name, lbx_files) do
      {:ok, {lbx, entries}} ->
        {images, pool} = build_tile_pool(lbx, entries, palette, images, 16, 64)
        {images, build_terrain_groups(pool)}

      {:error, _} ->
        {images, %{}}
    end
  end

  @fallback_tile_window 256

  defp find_default_lbx(lbx_files) do
    Enum.find(lbx_files, fn name ->
      String.downcase(name) == "compix.lbx"
    end)
  end

  defp open_default_lbx(mom_path, default_name, lbx_files) do
    candidates = Enum.uniq(List.wrap(default_name) ++ lbx_files)

    Enum.reduce_while(candidates, {:error, :no_lbx}, fn name, _acc ->
      path = Path.join(mom_path, name)

      case LBX.open(path) do
        {:ok, lbx} ->
          {:halt, {:ok, {lbx, LBX.entries(lbx)}}}

        _ ->
          {:cont, {:error, :no_lbx}}
      end
    end)
  end

  defp build_tile_pool(lbx, entries, palette, images, tile_size, target_count) do
    {images, pool, _window_start, _window_end} =
      Enum.reduce_while(entries, {images, [], nil, nil}, fn entry,
                                                            {images_acc, pool, window_start,
                                                             window_end} ->
        cond do
          entry.type != :image ->
            {:cont, {images_acc, pool, window_start, window_end}}

          window_end && entry.index > window_end ->
            {:halt, {images_acc, pool, window_start, window_end}}

          true ->
            case TileCache.fetch(lbx, entry.index, palette: palette) do
              {:ok, image} ->
                frame = List.first(image.frames)

                if frame && frame.width == tile_size && frame.height == tile_size do
                  window_start = window_start || entry.index
                  window_end = window_end || window_start + @fallback_tile_window - 1

                  if entry.index > window_end do
                    {:halt, {images_acc, pool, window_start, window_end}}
                  else
                    key = TileCache.key(lbx.path, entry.index, frame.index, image.palette_hash)
                    images_acc = Map.put_new(images_acc, key, encode_image(frame))

                    pool =
                      pool ++ [%{"key" => key, "width" => frame.width, "height" => frame.height}]

                    if length(pool) >= target_count do
                      {:halt, {images_acc, pool, window_start, window_end}}
                    else
                      {:cont, {images_acc, pool, window_start, window_end}}
                    end
                  end
                else
                  {:cont, {images_acc, pool, window_start, window_end}}
                end

              _ ->
                {:cont, {images_acc, pool, window_start, window_end}}
            end
        end
      end)

    {images, pool}
  end

  defp build_terrain_groups([]), do: %{}

  defp build_terrain_groups(pool) do
    pool_len = length(pool)

    Enum.reduce(0..255, %{}, fn terrain_id, acc ->
      entry = Enum.at(pool, rem(terrain_id, pool_len))
      Map.put(acc, "terrain_#{terrain_id}", [entry])
    end)
  end
end
