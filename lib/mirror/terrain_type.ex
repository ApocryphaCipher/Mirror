defmodule Mirror.TerrainType do
  @moduledoc """
  Resolves and matches terrain tile indices against their 8-way neighbours.

  This table and resolution algorithm are ported directly from the BSD-3 licensed
  kazzmir/master-of-magic remake (commit `e824e98`), specifically the
  `game/magic/terrain/{terrain.go,map.go}` files. Full license text and
  copyright notice: `NOTICE.md`.
  """

  @external_resource "priv/kazzmir_terrain_table.json"

  # Load and parse the table at compile time.
  raw_table =
    "priv/kazzmir_terrain_table.json"
    |> File.read!()
    |> Jason.decode!()

  # Normalize terrain strings to atoms (e.g. "Nature Node" -> :nature_node)
  normalize_type = fn type_str ->
    type_str
    |> String.downcase()
    |> String.replace(" ", "_")
    |> String.to_atom()
  end

  # Map kazzmir direction strings to our topology's 0..7 integer directions, plus :center
  parse_dir = fn
    "Center" -> :center
    "North" -> 0
    "NorthEast" -> 1
    "East" -> 2
    "SouthEast" -> 3
    "South" -> 4
    "SouthWest" -> 5
    "West" -> 6
    "NorthWest" -> 7
  end

  @tiles (for entry <- raw_table do
            index = entry["index"]
            terrain_type = normalize_type.(entry["terrain_type"])

            compatibilities =
              Map.new(entry["compatibilities"], fn {dir_str, rule} ->
                dir = parse_dir.(dir_str)
                # :any_of or :none_of
                rule_type = String.to_atom(rule["type"])
                terrains = Enum.map(rule["terrains"], normalize_type)
                {dir, {rule_type, terrains}}
              end)

            {index, terrain_type, compatibilities}
          end)
         |> Enum.sort_by(fn {idx, _, _} -> idx end)

  @doc """
  Returns the base terrain type (as an atom, e.g. `:ocean`, `:grass`) for a raw save tile value.
  Myrror tiles (>= 0x2FA) are mapped back to their Arcanus equivalent before lookup.
  Returns `nil` if the tile index is unknown.
  """
  @spec terrain_type(integer()) :: atom() | nil
  def terrain_type(tile_number) when tile_number >= 0x2FA do
    do_terrain_type(tile_number - 0x2FA)
  end

  def terrain_type(tile_number) when tile_number >= 0 do
    do_terrain_type(tile_number)
  end

  def terrain_type(_), do: nil

  # Generate O(1) pattern matching clauses for terrain_type and rules
  for {index, t_type, compat} <- @tiles do
    defp do_terrain_type(unquote(index)), do: unquote(t_type)
    defp tile_rules(unquote(index)), do: unquote(Macro.escape(compat))
  end

  defp do_terrain_type(_), do: nil
  defp tile_rules(_), do: nil

  # Tile 601 is the animated "sparkle" ocean. The game scatters it at random over
  # ordinary ocean (~20% of ocean tiles, including tiles beside shore), so it has
  # no rules of its own: checked live 2026-10-04, tile 0's rules accept all 1,213
  # real 601 tiles (3 worlds, both planes), while kazzmir's strict rule for 601
  # accepts only 700 of them. See docs/reference/classic-terrain-format.md.
  @sparkle_ocean 601
  @plain_ocean 0

  @doc """
  Checks if `tile_number` is compatible with the given `region`.

  The sparkle-ocean tile (601) is checked with plain ocean's rules (tile 0),
  because the game places it over any ocean tile regardless of neighbours. So
  `matches?(601, region) == matches?(0, region)`. `resolve_tile/2` still returns
  tile 0 for ocean; swapping some of those for 601 is a separate, cosmetic choice.

  `region` is a map of direction -> terrain type atom. Directions can be `0..7`
  (for N, NE, E, etc. per `Mirror.Engine.Topology`) or `:center`.

  A tile matches if for every direction present in `region`, it either has no constraint
  for that direction, or the `region`'s terrain type satisfies the tile's rule
  (`:any_of` / `:none_of`).
  """
  @spec matches?(integer(), map()) :: boolean()
  def matches?(tile_number, region) when is_map(region) do
    # Normalize tile number to Arcanus base
    base_tile = if tile_number >= 0x2FA, do: tile_number - 0x2FA, else: tile_number

    case tile_rules(canonical_tile(base_tile)) do
      nil -> false
      rules -> matches_rules?(rules, region)
    end
  end

  defp canonical_tile(@sparkle_ocean), do: @plain_ocean
  defp canonical_tile(tile), do: tile

  defp matches_rules?(rules, region) do
    Enum.all?(region, fn {dir, actual_type} ->
      case Map.get(rules, dir) do
        nil -> true
        {:any_of, allowed} -> actual_type in allowed
        {:none_of, forbidden} -> actual_type not in forbidden
      end
    end)
  end

  @doc """
  Finds the first valid tile number for the given `region` on the specified `plane`.

  `region` **must** include `:center` (the terrain type being resolved — what
  you're painting, or the tile's own current type when re-resolving after a
  neighbour changed). Every tile's own `:center` rule requires exactly its own
  terrain type, so restricting the scan to tiles whose type equals
  `region[:center]` returns the same first match kazzmir's two-phase
  `FindMatchingTile` would (its `OnlyTiles[center]` fast path, then a
  full-plane fallback that in practice can never find a different-typed tile,
  since every tile enforces its own `Center` rule whenever `:center` is
  present in the match).

  This is a deliberate difference from kazzmir: `FindMatchingTile` falls back
  to scanning the *entire* plane when `:center` is absent from `match`,
  ignoring type entirely — a call shape that in this codebase's usage never
  happens on purpose. Rather than port that fallback silently, a missing
  `:center` is a caller error here.

  Tiles are scanned in ascending index order — order matters, since more than
  one tile can satisfy the same `region` (e.g. decorative variants).
  """
  @spec resolve_tile(map(), :arcanus | :myrror) :: integer() | nil
  def resolve_tile(region, plane) when plane in [:arcanus, :myrror] and is_map(region) do
    case Map.fetch(region, :center) do
      {:ok, center_type} ->
        offset = if plane == :myrror, do: 0x2FA, else: 0

        match =
          Enum.find(@tiles, fn {_index, t_type, rules} ->
            t_type == center_type and matches_rules?(rules, region)
          end)

        case match do
          {index, _, _} -> index + offset
          nil -> nil
        end

      :error ->
        raise ArgumentError,
              "resolve_tile/2 requires :center in region, got: #{inspect(region)}"
    end
  end
end
