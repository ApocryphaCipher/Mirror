defmodule MirrorWeb.MoveTool do
  @moduledoc """
  The pure parts of the Move tool (STORY-019): which structure a click means (a city,
  a Tower of Wizardry or a lair), and what to tell the person after a click, an error
  or an undo. The record edits themselves are `Mirror.SaveFile.Structures`; the page
  (`MirrorWeb.MapLive`) only wires these to pointer events.
  """

  alias Mirror.SaveFile.{Cities, Structures}

  @type kind :: :city | :tower | :lair
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
    city_at(raw, plane, x, y) || tower_at(raw, x, y) || lair_at(raw, plane, x, y)
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

  @doc "Moves the picked structure; wraps the `Structures` move for its kind."
  @spec move(binary(), pending(), :arcanus | :myrror, integer(), integer()) ::
          {:ok, binary(), map()} | {:error, term()}
  def move(raw, %{kind: :city, index: index}, plane, x, y),
    do: Structures.move_city(raw, index, {x, y, plane_number(plane)})

  def move(raw, %{kind: :tower, index: index}, _plane, x, y),
    do: Structures.move_tower(raw, index, {x, y})

  def move(raw, %{kind: :lair, index: index}, plane, x, y),
    do: Structures.move_encounter(raw, index, {x, y, plane_number(plane)})

  @doc "The notice for a structure that was just picked up."
  def picked(%{name: name}),
    do: "Moving #{name}: click where it should go. Right-click, or click it again, to cancel."

  @doc "The notice after a move."
  def moved(%{name: name}, {x, y}, report) do
    "Moved #{name} to (#{x}, #{y})" <> followed(report) <> "." <> warnings(report)
  end

  defp followed(%{garrison: n, followed: followed}) do
    parts =
      [garrison(n) | Enum.map(followed, &follower/1)]
      |> Enum.reject(&is_nil/1)

    if parts == [], do: "", else: " with its " <> Enum.join(parts, " and ")
  end

  defp followed(%{garrison: 0}), do: ""
  defp followed(%{garrison: n}), do: " with " <> garrison(n)
  defp followed(_report), do: ""

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
  def error_message(:encounter_at_destination), do: "There is already a lair there."

  def error_message(:foreign_units_at_destination),
    do: "Another player's units are standing there."

  def error_message(reason) when reason in [:no_such_city, :no_such_tower, :no_such_encounter],
    do: "That is not in the save any more."

  def error_message(_other), do: "It could not be moved there."
end
