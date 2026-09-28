defmodule Mirror.TerrainType do
  @moduledoc """
  Resolves and matches terrain tile indices against their 8-way neighbours.

  This table and resolution algorithm are ported directly from the BSD-3 licensed
  kazzmir/master-of-magic remake (commit `e824e98`), specifically the
  `game/magic/terrain/{terrain.go,map.go}` files.
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

  @doc """
  Checks if `tile_number` is compatible with the given `region`.

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

    case tile_rules(base_tile) do
      nil -> false
      rules -> matches_rules?(rules, region)
    end
  end

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

  Tiles are scanned in ascending index order. To optimize, only tiles whose intrinsic
  `:center` terrain type equals `region[:center]` are considered.
  """
  @spec resolve_tile(map(), :arcanus | :myrror) :: integer() | nil
  def resolve_tile(region, plane) when plane in [:arcanus, :myrror] and is_map(region) do
    center_type = Map.get(region, :center)
    offset = if plane == :myrror, do: 0x2FA, else: 0

    match =
      Enum.find(@tiles, fn {_index, t_type, rules} ->
        t_type == center_type and matches_rules?(rules, region)
      end)

    case match do
      {index, _, _} -> index + offset
      nil -> nil
    end
  end
end
