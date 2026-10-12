defmodule MirrorWeb.UnitPanel do
  @moduledoc """
  What the units panel shows (STORY-020) and says: the units standing on one tile, in words,
  and the notices for moving some of them (`Mirror.SaveFile.Structures.move_units/3`). Pure; the
  page (`MirrorWeb.MapLive`) draws it.
  """

  alias Mirror.SaveFile.{UnitTypes, Units, Wizards}

  @sentry 1
  @goto 3
  @idle 4

  @doc "The units on `{x, y, plane}` (plane 0 or 1) as rows for the panel, in save order."
  @spec rows(binary(), {integer(), integer(), 0 | 1}) :: [map()]
  def rows(raw, {_x, _y, _plane} = tile) do
    names = Wizards.names(raw)

    for u <- Units.stack(raw, tile) do
      %{
        index: u.index,
        type: u.type,
        name: UnitTypes.display_name(u.type),
        owner: u.owner,
        owner_name: Map.get(names, u.owner, "Neutral"),
        level: u.level,
        experience: u.experience,
        damage: u.damage,
        orders: orders(u)
      }
    end
  end

  # Status 3 is a go-to order and always has a target in the saves; 4 is what the game gives a unit
  # with no orders when a turn resolves (seen: units moved with status 0 became 4 after End Turn);
  # 1 is sentry (*guess* from the save counts).
  defp orders(%{status: @goto, destination: {x, y}}), do: "going to (#{x}, #{y})"
  defp orders(%{status: @sentry}), do: "sentry"
  defp orders(%{status: @idle}), do: nil
  defp orders(_unit), do: nil

  @doc """
  The ids the units form posted (`%{"picked" => ["3", "5"]}`) as integers, kept to the ones that
  are really on the tile. `{:error, :no_units}` when none is ticked, `{:error, :bad_units}` for
  anything that is not a list of whole numbers.
  """
  @spec picked(map() | nil, [map()]) ::
          {:ok, [non_neg_integer()]} | {:error, :no_units | :bad_units}
  def picked(params, rows) do
    case params do
      %{"picked" => list} when is_list(list) -> parse_picked(list, rows)
      %{"picked" => _} -> {:error, :bad_units}
      _ -> {:error, :no_units}
    end
  end

  defp parse_picked([], _rows), do: {:error, :no_units}

  defp parse_picked(list, rows) do
    ids =
      Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acc} ->
        case is_binary(value) && Integer.parse(value) do
          {n, ""} -> {:cont, {:ok, [n | acc]}}
          _ -> {:halt, :error}
        end
      end)

    on_tile = MapSet.new(rows, & &1.index)

    case ids do
      {:ok, ids} ->
        ids = ids |> Enum.reverse() |> Enum.uniq()

        if Enum.all?(ids, &MapSet.member?(on_tile, &1)),
          do: {:ok, ids},
          else: {:error, :bad_units}

      :error ->
        {:error, :bad_units}
    end
  end

  @doc "The notice for the units that are picked up and waiting for a destination."
  def armed(count),
    do: "Moving #{count} #{unit_word(count)}: click where they should go. Right-click to cancel."

  @doc "The notice after a move, with the heads-up for any warning."
  def moved(count, {x, y}, warnings),
    do: "Moved #{count} #{unit_word(count)} to (#{x}, #{y})." <> warning_text(warnings)

  defp warning_text([]), do: ""

  defp warning_text(warnings) do
    " " <>
      Enum.map_join(warnings, " ", fn
        {:cannot_be_on_water, types} ->
          "Heads up: #{names(types)} cannot stand on water by themselves."

        {:boat_on_land, types} ->
          "Heads up: #{names(types)} can only be on water, or in a city."
      end)
  end

  defp names(types), do: types |> Enum.map(&UnitTypes.display_name/1) |> Enum.join(", ")

  defp unit_word(1), do: "unit"
  defp unit_word(_), do: "units"

  @doc "What went wrong, in words."
  def error_message(:off_map), do: "That is off the map."
  def error_message(:no_units), do: "Tick at least one unit to move."
  def error_message(:bad_units), do: "Those are not units on this tile."
  def error_message(:no_such_unit), do: "Those units are not in the save any more."
  def error_message(:mixed_owners), do: "Those units belong to different players."
  def error_message(:foreign_city_at_destination), do: "That tile holds another player's city."

  def error_message(:foreign_units_at_destination),
    do: "Another player's units are standing there."

  def error_message(:stack_full), do: "A tile holds at most 9 units."
  def error_message(_other), do: "The units could not be moved there."
end
