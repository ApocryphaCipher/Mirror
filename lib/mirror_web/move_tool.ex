defmodule MirrorWeb.MoveTool do
  @moduledoc """
  The pure parts of the Move tool (STORY-019): which structure a click means (a city,
  a Tower of Wizardry or a lair), and what to tell the person after a click, an error
  or an undo. The record edits themselves are `Mirror.SaveFile.Structures`; the page
  (`MirrorWeb.MapLive`) only wires these to pointer events.
  """

  import Bitwise

  alias Mirror.SaveFile.{Cities, Structures}

  @type kind :: :city | :tower | :lair | :node
  @type pending :: %{kind: kind(), index: non_neg_integer(), name: String.t()}

  # Encounter kinds that can be moved on their own, named as in
  # docs/reference/kazzmir-save-layouts.md.
  @lair_names %{
    4 => "cave",
    5 => "dungeon",
    6 => "ancient temple",
    7 => "abandoned keep",
    8 => "monster lair",
    9 => "ruins",
    10 => "fallen temple"
  }

  @doc """
  The structure standing on `{x, y}` of `plane`, or `nil`. A city wins over a tower,
  and a tower over a lair, if more than one share a tile.
  """
  @spec pick_at(binary(), :arcanus | :myrror, integer(), integer()) :: pending() | nil
  def pick_at(raw, plane, x, y) do
    city_at(raw, plane, x, y) || tower_at(raw, x, y) || lair_at(raw, plane, x, y) ||
      node_at(raw, plane, x, y)
  end

  @node_names %{0 => "Sorcery", 1 => "Nature", 2 => "Chaos"}

  defp node_at(raw, plane, x, y) do
    case Structures.node_at(raw, x, y, plane_number(plane)) do
      %{index: index, type: type} ->
        %{kind: :node, index: index, name: "the #{Map.fetch!(@node_names, type)} node"}

      nil ->
        nil
    end
  end

  defp city_at(raw, plane, x, y) do
    with {:ok, cities} <- Cities.parse(raw),
         %{index: index, name: name} <-
           Enum.find(cities, &(&1.plane == plane and &1.x == x and &1.y == y)) do
      %{kind: :city, index: index, name: name}
    else
      _ -> nil
    end
  end

  defp tower_at(raw, x, y) do
    case Structures.tower_at(raw, x, y) do
      %{index: index} -> %{kind: :tower, index: index, name: "the Tower of Wizardry"}
      nil -> nil
    end
  end

  defp lair_at(raw, plane, x, y) do
    case Structures.encounter_at(raw, x, y, plane_number(plane)) do
      %{index: index, kind: kind} ->
        %{kind: :lair, index: index, name: "the #{Map.get(@lair_names, kind, "lair")}"}

      nil ->
        nil
    end
  end

  @doc "True when both picks name the same structure."
  def same?(%{kind: kind, index: index}, %{kind: kind, index: index}), do: true
  def same?(_a, _b), do: false

  @doc "The plane number the save stores: 0 Arcanus, 1 Myrror."
  def plane_number(:arcanus), do: 0
  def plane_number(:myrror), do: 1

  @doc """
  Moves the picked structure; wraps the `Structures` move for its kind. A node needs
  `terrain_at`, a function from `{x, y}` to the plane's terrain tile there (`Structures.move_node/4`);
  the others ignore it.
  """
  @spec move(
          binary(),
          pending(),
          :arcanus | :myrror,
          integer(),
          integer(),
          ({integer(), integer()} -> integer()) | nil
        ) :: {:ok, binary(), map()} | {:error, term()}
  def move(raw, pending, plane, x, y, terrain_at \\ nil)

  def move(raw, %{kind: :city, index: index}, plane, x, y, _terrain_at),
    do: Structures.move_city(raw, index, {x, y, plane_number(plane)})

  def move(raw, %{kind: :tower, index: index}, _plane, x, y, _terrain_at),
    do: Structures.move_tower(raw, index, {x, y})

  def move(raw, %{kind: :lair, index: index}, plane, x, y, _terrain_at),
    do: Structures.move_encounter(raw, index, {x, y, plane_number(plane)})

  # A node is its terrain tile: the caller says what tile is where (`terrain_at`), and gets the
  # two tile changes back in the report to apply as map edits (see `terrain_edits/1`).
  def move(raw, %{kind: :node, index: index}, _plane, x, y, terrain_at)
      when is_function(terrain_at, 1),
      do: Structures.move_node(raw, index, {x, y}, terrain_at)

  # (the same bits as `road_edits/4` below: a plain road 0x08 and an enchanted one 0x10)
  @node_road_bits 0x18

  @doc """
  The map edits that go with a moved node, in the form `Editor.apply_record/5` takes (none for
  anything else): the terrain (`Mirror.NodeTerrain.edits/4`: the old tile back to land, the new
  tile the node) and the roads on the tile it lands on, which are removed. `terrain` is the plane's
  terrain bytes and `flags` the destination's `terrain_flags` byte.
  """
  @spec terrain_edits(map(), binary(), integer() | nil) :: [tuple()]
  def terrain_edits(%{moved: :node, from: from, to: {x, y} = to, node_tile: tile}, terrain, flags) do
    terrain_edit = {:terrain, Mirror.NodeTerrain.edits(terrain, from, to, tile)}

    if is_integer(flags) and (flags &&& @node_road_bits) != 0,
      do: [terrain_edit, {:terrain_flags, [{x, y, flags &&& bnot(@node_road_bits)}]}],
      else: [terrain_edit]
  end

  def terrain_edits(_report, _terrain, _flags), do: []

  @road 0x08
  @road_bits 0x18

  @doc """
  The tile edits that go with putting a city down: the game keeps a road under every
  city (all 31 cities of a turn-one save, all 34 of a played one), and a city whose tile
  has none is not joined to its neighbours' roads (checked 2026-10-11, STORY-019). So a
  city moved onto a tile with no road gets a plain one. `flags` is the tile's current
  `terrain_flags` byte. Towers and lairs get nothing.
  """
  @spec road_edits(pending(), integer() | nil, integer(), integer()) :: [tuple()]
  def road_edits(%{kind: :city}, flags, x, y)
      when is_integer(flags) and (flags &&& @road_bits) == 0,
      do: [{:terrain_flags, [{x, y, flags ||| @road}]}]

  def road_edits(_pending, _flags, _x, _y), do: []

  @doc "The notice for a structure that was just picked up."
  def picked(%{name: name}),
    do: "Moving #{name}: click where it should go. Right-click, or click it again, to cancel."

  @doc "The notice after a move."
  def moved(%{name: name}, {x, y}, report, road? \\ false, road_removed? \\ false) do
    "Moved #{name} to (#{x}, #{y})" <>
      followed(report) <>
      "." <>
      if(road?, do: " Laid a road under it.", else: "") <>
      if(road_removed?, do: " Removed the road that was there.", else: "") <> warnings(report)
  end

  defp followed(%{garrison: n, followed: followed}) do
    parts =
      [garrison(n) | Enum.map(followed, &follower/1)]
      |> Enum.reject(&is_nil/1)

    if parts == [], do: "", else: " with its " <> Enum.join(parts, " and ")
  end

  defp followed(%{moved: :node, guardians: g, units: u}) do
    parts = Enum.reject([count(g, "guardian record", "guardian records"), garrison(u)], &is_nil/1)
    if parts == [], do: "", else: " with its " <> Enum.join(parts, " and ")
  end

  defp followed(%{garrison: 0}), do: ""
  defp followed(%{garrison: n}), do: " with " <> garrison(n)
  defp followed(_report), do: ""

  defp count(0, _one, _many), do: nil
  defp count(1, one, _many), do: "1 #{one}"
  defp count(n, _one, many), do: "#{n} #{many}"

  defp garrison(0), do: nil
  defp garrison(1), do: "unit"
  defp garrison(n), do: "#{n} units"

  defp follower(:summoning_circle), do: "summoning circle"
  defp follower(:fortress), do: "fortress"

  # A tower stands on both planes; the game loads one on ocean, where land units
  # cannot reach it (checked 2026-10-10).
  defp warnings(%{warnings: [_ | _] = warnings}) do
    planes = Enum.map_join(warnings, " and ", fn {:water, plane} -> plane_name(plane) end)
    " Heads up: that tile is water on #{planes}, so land units cannot reach it there."
  end

  defp warnings(_report), do: ""

  defp plane_name(:arcanus), do: "Arcanus"
  defp plane_name(:myrror), do: "Myrror"

  @doc "What went wrong, in words."
  def error_message(:off_map), do: "That is off the map."
  def error_message(:city_at_destination), do: "There is already a city there."
  def error_message(:tower_at_destination), do: "There is already a tower there."
  def error_message(:node_at_destination), do: "There is already a node there."
  def error_message(:same_tile), do: "That is where it already is."
  def error_message(:aura_off_map), do: "The node's aura would run off the map there."

  def error_message(:bad_terrain),
    do:
      "A node can go on land (grass, forest, swamp, desert, tundra, hills or mountains), not on water, a river, a lake, a volcano or the polar rows."

  def error_message(:stack_full),
    do: "A tile holds at most 9 units, and the node's units would not fit there."

  def error_message(:encounter_at_destination), do: "There is already a lair there."

  def error_message(:foreign_units_at_destination),
    do: "Another player's units are standing there."

  def error_message(reason) when reason in [:no_such_city, :no_such_tower, :no_such_encounter],
    do: "That is not in the save any more."

  def error_message(_other), do: "It could not be moved there."
end
