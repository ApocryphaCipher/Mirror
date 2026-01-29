defmodule Mirror.Paths do
  @moduledoc """
  Resolve filesystem locations for Master of Magic assets and caches.
  """

  def mom_path do
    System.get_env("MIRROR_MOM_PATH") || Application.get_env(:mirror, :mom_path)
  end

  def asset_map_dir do
    System.get_env("MIRROR_ASSET_MAP") || Application.get_env(:mirror, :asset_map_dir)
  end

  def tile_cache_dir do
    System.get_env("MIRROR_TILE_CACHE") || Application.get_env(:mirror, :tile_cache_dir)
  end

  def momime_resources_dir do
    System.get_env("MIRROR_MOMIME_RES_PATH") ||
      Application.get_env(:mirror, :momime_resources_dir) ||
      Path.expand("../../resources", __DIR__)
  end
end
