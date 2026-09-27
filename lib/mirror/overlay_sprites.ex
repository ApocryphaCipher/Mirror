defmodule Mirror.OverlaySprites do
  @moduledoc """
  Overland sprites for the map's overlay layers, sent to the browser as
  palette indices (not RGBA) so the client can recolour banner pixels per
  owner. Entry numbers are from the sprite catalog in
  docs/reference/overland-sprites-and-save-blocks.md.
  """

  alias Mirror.LBX
  alias Mirror.LBX.Palette

  # #20 MAPCITY is what the game draws for every city, walled or not
  # (checked in DOSBox, STORY-032). #21 CITYNOWA's frames are #20's without
  # the stone ring; its use is unknown.
  @cities %{city: 20, citynowa: 21}

  # Normal roads: #45 centre piece + #46..#53 direction pieces (N, NE, E, SE, S, SW, W, NW)
  @roads %{
    c: 45,
    n: 46,
    ne: 47,
    e: 48,
    se: 49,
    s: 50,
    sw: 51,
    w: 52,
    nw: 53
  }

  # Enchanted roads: #54 centre piece + #55..#62 direction pieces (6 frames)
  @enchanted_roads %{
    c: 54,
    n: 55,
    ne: 56,
    e: 57,
    se: 58,
    s: 59,
    sw: 60,
    w: 61,
    nw: 62
  }

  # Specials (minerals, food): MAPBACK.LBX #78..#86, #91, #92
  @specials %{
    iron: 78,
    coal: 79,
    silver: 80,
    gold: 81,
    gems: 82,
    mithril: 83,
    adamantium: 84,
    quork: 85,
    crysx: 86,
    nightshade: 91,
    wild_game: 92
  }

  # Corruption icon: MAPBACK.LBX #77 (22x18)
  @corruption %{corruption: 77}

  # Unit plaques: MAPBACK.LBX #14..#19 (20x18, one per banner colour)
  @plaques %{
    blue: 14,
    green: 15,
    purple: 16,
    red: 17,
    yellow: 18,
    neutral: 19
  }

  @doc """
  `%{palette: base64 RGBA (index 0 transparent), cities: %{...}, roads: %{...},
  enchanted_roads: %{...}, specials: %{...}, corruption: %{...}, plaques: %{...},
  units: %{...}}`, each sprite `%{width, height, frames: [base64 indices]}`, or
  `{:error, reason}` when `MAPBACK.LBX` isn't in `dir`. `UNITS1.LBX`/`UNITS2.LBX`
  are both optional in `Mirror.GameFiles.manifest/0` (an install may have
  `MAPBACK.LBX` without them), so a missing unit bank degrades to an empty
  `units` map rather than failing the whole load and hiding cities/roads/etc.
  """
  def load(dir) when dir in [nil, ""], do: {:error, :no_mom_path}

  def load(dir) do
    with {:ok, mapback_name} <- find(dir, "MAPBACK.LBX"),
         {:ok, mapback} <- LBX.open(Path.join(dir, mapback_name)),
         {:ok, palette} <- LBX.game_palette(dir),
         {:ok, cities} <- sprites(mapback, @cities),
         {:ok, roads} <- sprites(mapback, @roads),
         {:ok, enchanted_roads} <- sprites(mapback, @enchanted_roads),
         {:ok, specials} <- sprites(mapback, @specials),
         {:ok, corruption} <- sprites(mapback, @corruption),
         {:ok, plaques} <- sprites(mapback, @plaques) do
      {:ok,
       %{
         palette: Base.encode64(Palette.to_binary(palette)),
         cities: cities,
         roads: roads,
         enchanted_roads: enchanted_roads,
         specials: specials,
         corruption: corruption,
         plaques: plaques,
         units: load_units(dir)
       }}
    end
  end

  # UNITS1.LBX/UNITS2.LBX are optional (Mirror.GameFiles.manifest/0): fall
  # back to no unit figures rather than failing the whole sprite load.
  defp load_units(dir) do
    with {:ok, u1_name} <- find(dir, "UNITS1.LBX"),
         {:ok, u1} <- LBX.open(Path.join(dir, u1_name)),
         {:ok, u2_name} <- find(dir, "UNITS2.LBX"),
         {:ok, u2} <- LBX.open(Path.join(dir, u2_name)),
         {:ok, units1} <- unit_sprites(u1, 0..119//1, 0),
         {:ok, units2} <- unit_sprites(u2, 0..77//1, 120) do
      Map.merge(units1, units2)
    else
      _ -> %{}
    end
  end

  defp sprites(lbx, entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn {key, index}, {:ok, acc} ->
      case LBX.decode_image(lbx, index, palette: :grayscale) do
        {:ok, image} ->
          sprite = %{
            width: image.width,
            height: image.height,
            frames: Enum.map(image.frames, &Base.encode64(&1.indices))
          }

          {:cont, {:ok, Map.put(acc, key, sprite)}}

        {:error, reason} ->
          {:halt, {:error, {:sprite, index, reason}}}
      end
    end)
  end

  defp unit_sprites(lbx, range, offset) do
    Enum.reduce_while(range, {:ok, %{}}, fn i, {:ok, acc} ->
      case LBX.decode_image(lbx, i, palette: :grayscale) do
        {:ok, image} ->
          sprite = %{
            width: image.width,
            height: image.height,
            frames: Enum.map(image.frames, &Base.encode64(&1.indices))
          }

          {:cont, {:ok, Map.put(acc, offset + i, sprite)}}

        {:error, reason} ->
          {:halt, {:error, {:unit_sprite, offset + i, reason}}}
      end
    end)
  end

  defp find(dir, wanted) do
    case Enum.find(LBX.list_files(dir), &(String.upcase(&1) == wanted)) do
      nil -> {:error, {:missing, wanted}}
      name -> {:ok, name}
    end
  end
end
