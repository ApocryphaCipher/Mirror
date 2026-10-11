defmodule MirrorWeb.MoveTool do
  @moduledoc """
  The pure parts of the Move city tool (STORY-019): which city a click means, and
  what to tell the person after a click, an error or an undo. The record edit
  itself is `Mirror.SaveFile.Structures.move_city/3`; the page
  (`MirrorWeb.MapLive`) only wires these to pointer events.
  """

  alias Mirror.SaveFile.{Cities, Structures}

  @type pending :: %{index: non_neg_integer(), name: String.t()}

  @doc "The city standing on `{x, y}` of `plane`, as `%{index, name}`, or `nil`."
  @spec city_at(binary(), :arcanus | :myrror, integer(), integer()) :: pending() | nil
  def city_at(raw, plane, x, y) do
    with {:ok, cities} <- Cities.parse(raw),
         %{index: index, name: name} <-
           Enum.find(cities, &(&1.plane == plane and &1.x == x and &1.y == y)) do
      %{index: index, name: name}
    else
      _ -> nil
    end
  end

  @doc "The plane number the save stores: 0 Arcanus, 1 Myrror."
  def plane_number(:arcanus), do: 0
  def plane_number(:myrror), do: 1

  @doc "Moves the picked city, or `{:error, reason}`; wraps `Structures.move_city/3`."
  @spec move(binary(), pending(), :arcanus | :myrror, integer(), integer()) ::
          {:ok, binary(), map()} | {:error, term()}
  def move(raw, %{index: index}, plane, x, y) do
    Structures.move_city(raw, index, {x, y, plane_number(plane)})
  end

  @doc "The notice for a city that was just picked up."
  def picked(%{name: name}),
    do: "Moving #{name}: click where it should go. Right-click, or click it again, to cancel."

  @doc "The notice after a move."
  def moved(%{name: name}, {x, y}, report) do
    "Moved #{name} to (#{x}, #{y})" <> followed(report) <> "."
  end

  defp followed(%{garrison: n, followed: followed}) do
    parts =
      [garrison(n) | Enum.map(followed, &follower/1)]
      |> Enum.reject(&is_nil/1)

    if parts == [], do: "", else: " with its " <> Enum.join(parts, " and ")
  end

  defp garrison(0), do: nil
  defp garrison(1), do: "unit"
  defp garrison(n), do: "#{n} units"

  defp follower(:summoning_circle), do: "summoning circle"
  defp follower(:fortress), do: "fortress"

  @doc "What went wrong, in words."
  def error_message(:off_map), do: "That is off the map."
  def error_message(:city_at_destination), do: "There is already a city there."

  def error_message(:foreign_units_at_destination),
    do: "Another player's units are standing there."

  def error_message(:no_such_city), do: "That city is not in the save any more."
  def error_message(_other), do: "The city could not be moved there."
end
