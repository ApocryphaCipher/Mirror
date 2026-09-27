defmodule Mirror.OverlaySpritesTest do
  use ExUnit.Case, async: true

  alias Mirror.OverlaySprites

  @mom_path System.get_env("MIRROR_MOM_PATH", "")
  @has_game_files @mom_path != "" and File.exists?(Path.join(@mom_path, "MAPBACK.LBX"))

  test "load/1 returns error for nil or empty path" do
    assert OverlaySprites.load(nil) == {:error, :no_mom_path}
    assert OverlaySprites.load("") == {:error, :no_mom_path}
  end

  @tag skip: !@has_game_files && "needs MAPBACK.LBX in MIRROR_MOM_PATH"
  test "load/1 decodes cities, roads, enchanted_roads, specials, and corruption sprites" do
    assert {:ok, sprites} = OverlaySprites.load(@mom_path)

    assert is_binary(sprites.palette)
    assert Map.has_key?(sprites.cities, :city)
    assert Map.has_key?(sprites.cities, :citynowa)

    # Roads: centre piece + 8 direction pieces
    for piece <- [:c, :n, :ne, :e, :se, :s, :sw, :w, :nw] do
      assert %{width: 20, height: 18, frames: [_]} = sprites.roads[piece]
      assert %{width: 20, height: 18, frames: frames} = sprites.enchanted_roads[piece]
      assert length(frames) == 6
    end

    # Specials: 11 specials
    for special <- [
          :iron,
          :coal,
          :silver,
          :gold,
          :gems,
          :mithril,
          :adamantium,
          :quork,
          :crysx,
          :wild_game,
          :nightshade
        ] do
      assert %{width: 20, height: 18, frames: [_]} = sprites.specials[special]
    end

    # Corruption: 22x18 (wider than standard 20x18)
    assert %{width: 22, height: 18, frames: [_]} = sprites.corruption.corruption
  end
end
