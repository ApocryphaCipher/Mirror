defmodule Mirror.AssetMap do
  @moduledoc """
  Persist user-labeled tile mappings.
  """

  require Logger

  alias Mirror.Paths

  @terrain_file "terrain_tiles.json"
  @overlay_file "overlay_tiles.json"

  def load(kind) when kind in [:terrain, :overlay] do
    path = map_path(kind)

    case File.read(path) do
      {:ok, raw} ->
        case Jason.decode(raw) do
          {:ok, data} when is_map(data) -> data
          _ -> %{}
        end

      {:error, _} ->
        %{}
    end
  end

  def save(kind, map) when kind in [:terrain, :overlay] and is_map(map) do
    path = map_path(kind)
    :ok = File.mkdir_p(Path.dirname(path))
    File.write(path, Jason.encode!(map, pretty: true))
  end

  def add_entry(kind, group, entry) when kind in [:terrain, :overlay] do
    map = load(kind)
    group = String.trim(group || "")

    if group == "" do
      {:error, :missing_group}
    else
      updated =
        Map.update(map, group, [entry], fn entries ->
          if Enum.any?(entries, &same_entry?(&1, entry)) do
            entries
          else
            entries ++ [entry]
          end
        end)

      case save(kind, updated) do
        :ok -> {:ok, updated}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp map_path(kind) do
    base = Paths.asset_map_dir() || default_map_dir()
    filename = if kind == :terrain, do: @terrain_file, else: @overlay_file
    Path.join(base, filename)
  end

  defp default_map_dir do
    Path.expand("../../priv/asset_map", __DIR__)
  end

  defp same_entry?(left, right) do
    Map.get(left, "lbx") == Map.get(right, "lbx") and
      Map.get(left, "index") == Map.get(right, "index") and
      Map.get(left, "frame") == Map.get(right, "frame") and
      Map.get(left, "variant") == Map.get(right, "variant")
  end
end
