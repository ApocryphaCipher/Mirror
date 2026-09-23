defmodule Mirror.TileAtlas do
  @moduledoc """
  Build the client tile atlas from the game's own `TERRAIN.LBX`.

  A save's terrain value is a tile number into that file, so this is the
  only terrain backend (see docs/reference/classic-terrain-format.md).
  Returns `nil` when `MIRROR_MOM_PATH` has no `TERRAIN.LBX` + `FONTS.LBX`;
  the map then renders raw values instead of art.
  """

  require Logger

  alias Mirror.{Paths, TerrainLbx}

  def build do
    case TerrainLbx.load(Paths.mom_path()) do
      {:ok, terrain} ->
        %{backend: :terrain_lbx, terrain_lbx: TerrainLbx.payload(terrain)}

      {:error, reason} ->
        Logger.warning("No terrain art: TERRAIN.LBX unavailable (#{inspect(reason)})")
        nil
    end
  end
end
