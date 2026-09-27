defmodule Mirror.SaveFile.Roads do
  @moduledoc """
  Decodes overland roads, minerals/specials, and corruption from the
  `:terrain_flags` and `:minerals` save layers (STORY-013).

  Entry numbers and bit layouts are from:
  - `docs/reference/kazzmir-save-layouts.md`
  - `docs/reference/overland-sprites-and-save-blocks.md`
  """

  import Bitwise

  alias Mirror.Engine.Topology

  @map_width 60
  @map_height 40

  # Direction order from Mirror.Engine.Topology.dir_delta/1:
  # 0: N, 1: NE, 2: E, 3: SE, 4: S, 5: SW, 6: W, 7: NW.
  # Matches the MAPBACK.LBX road pieces #46..#53 / #55..#62.
  @piece_directions %{
    0 => :n,
    1 => :ne,
    2 => :e,
    3 => :se,
    4 => :s,
    5 => :sw,
    6 => :w,
    7 => :nw
  }

  # Minerals map byte value (0x013554) to special name atom. Ore/gem/crystal
  # ids live in the low nibble; wild game (0x40) and nightshade (0x80) are
  # independent flag bits that can combine with an ore nibble or with each
  # other on the same byte. Mirrors Mirror.Surveyor's own decoder
  # (lib/mirror/surveyor.ex `feature/7`) bit-for-bit, so the overlay and the
  # Surveyor tooltip never disagree about the same tile.
  # Ground truth: checked in live RAM and Surveyor (docs/reference/kazzmir-save-layouts.md).
  # Note: #78 is iron and #79 is coal.
  @ore_nibble 0x0F
  @wild_game_bit 0x40
  @nightshade_bit 0x80

  @specials %{
    1 => :iron,
    2 => :coal,
    3 => :silver,
    4 => :gold,
    5 => :gems,
    6 => :mithril,
    7 => :adamantium,
    8 => :quork,
    9 => :crysx
  }

  @doc """
  Map of ore/gem/crystal nibble values to special icon names. Excludes the
  wild game and nightshade flag bits, which `special_for_value/1` checks
  separately.
  """
  def specials_map, do: @specials

  @doc """
  Maps a minerals byte value to its special atom, or `nil` if unmapped / none.
  Masks the ore/gem/crystal nibble and checks the wild game / nightshade flag
  bits independently (same precedence as `Mirror.Surveyor`): an ore/gem/
  crystal nibble wins over wild game, which wins over nightshade.
  """
  def special_for_value(value) when is_integer(value) do
    cond do
      Map.has_key?(@specials, value &&& @ore_nibble) ->
        Map.fetch!(@specials, value &&& @ore_nibble)

      (value &&& @wild_game_bit) != 0 ->
        :wild_game

      (value &&& @nightshade_bit) != 0 ->
        :nightshade

      true ->
        nil
    end
  end

  def special_for_value(_), do: nil

  @doc """
  Default overland map topology (60x40, wrap_x: true, wrap_y: false).
  """
  def default_topology do
    Topology.new(w: @map_width, h: @map_height, wrap_x: true, wrap_y: false)
  end

  @doc """
  Returns true if the tile's terrain_flags byte indicates a road (bit 0x08 or 0x10).
  """
  def road?(flag) when is_integer(flag), do: (flag &&& 0x18) != 0
  def road?(_), do: false

  @doc """
  Returns true if the tile's terrain_flags byte indicates an enchanted road (bit 0x10).
  """
  def enchanted_road?(flag) when is_integer(flag), do: (flag &&& 0x10) != 0
  def enchanted_road?(_), do: false

  @doc """
  Returns true if the tile's terrain_flags byte indicates corruption (bit 0x20).
  """
  def corrupted?(flag) when is_integer(flag), do: (flag &&& 0x20) != 0
  def corrupted?(_), do: false

  @doc """
  Returns the list of road pieces for a tile at `{x, y}` as a list of piece
  keys (`[:c, :n, ...]`), or an empty list if the tile has no road.
  """
  def road_pieces(flags, x, y, topo \\ default_topology())

  def road_pieces(flags, x, y, %Topology{} = topo) when is_binary(flags) do
    idx = y * topo.w + x

    if idx >= 0 and idx < byte_size(flags) do
      flag = :binary.at(flags, idx)

      if road?(flag) do
        neighbor_pieces =
          for dir <- 0..7,
              {:ok, {nx, ny}} <- [Topology.neighbor(topo, x, y, dir)],
              n_idx = ny * topo.w + nx,
              n_idx >= 0 and n_idx < byte_size(flags),
              n_flag = :binary.at(flags, n_idx),
              road?(n_flag) do
            Map.fetch!(@piece_directions, dir)
          end

        [:c | neighbor_pieces]
      else
        []
      end
    else
      []
    end
  end

  def road_pieces(_flags, _x, _y, _topo), do: []

  @doc """
  Decodes all road items from a `:terrain_flags` plane binary.
  Returns a list of `%{kind: :road, x: x, y: y, pieces: pieces, enchanted: boolean}`.
  """
  def road_items(flags, topo \\ default_topology())

  def road_items(flags, %Topology{} = topo) when is_binary(flags) do
    limit = min(byte_size(flags), topo.w * topo.h)

    for i <- 0..(limit - 1)//1,
        flag = :binary.at(flags, i),
        road?(flag) do
      x = rem(i, topo.w)
      y = div(i, topo.w)
      pieces = road_pieces(flags, x, y, topo)
      enchanted = enchanted_road?(flag)

      %{
        kind: :road,
        x: x,
        y: y,
        pieces: pieces,
        enchanted: enchanted
      }
    end
  end

  def road_items(_flags, _topo), do: []

  @doc """
  Decodes all mineral/special items from a `:minerals` plane binary.
  Returns a list of `%{kind: :special, x: x, y: y, special: special}`.
  """
  def special_items(minerals, w \\ @map_width, h \\ @map_height)

  def special_items(minerals, w, h)
      when is_binary(minerals) and is_integer(w) and is_integer(h) do
    limit = min(byte_size(minerals), w * h)

    for i <- 0..(limit - 1)//1,
        val = :binary.at(minerals, i),
        special = special_for_value(val),
        special != nil do
      %{
        kind: :special,
        x: rem(i, w),
        y: div(i, w),
        special: special
      }
    end
  end

  def special_items(_minerals, _w, _h), do: []

  @doc """
  Decodes all corruption items from a `:terrain_flags` plane binary.
  Returns a list of `%{kind: :corruption, x: x, y: y}`.
  """
  def corruption_items(flags, w \\ @map_width, h \\ @map_height)

  def corruption_items(flags, w, h) when is_binary(flags) and is_integer(w) and is_integer(h) do
    limit = min(byte_size(flags), w * h)

    for i <- 0..(limit - 1)//1,
        flag = :binary.at(flags, i),
        corrupted?(flag) do
      %{
        kind: :corruption,
        x: rem(i, w),
        y: div(i, w)
      }
    end
  end

  def corruption_items(_flags, _w, _h), do: []

  @doc """
  Combines roads, specials, and corruption items into a single list for the
  `"roads"` overlay layer. Roads are ordered first, followed by specials, then corruption.
  """
  def items(flags, minerals, topo \\ default_topology())

  def items(flags, minerals, %Topology{} = topo) do
    road_items(flags, topo) ++
      special_items(minerals, topo.w, topo.h) ++
      corruption_items(flags, topo.w, topo.h)
  end

  def items(_flags, _minerals, _topo), do: []
end
