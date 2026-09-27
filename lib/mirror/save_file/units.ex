defmodule Mirror.SaveFile.Units do
  @moduledoc """
  Decodes the units block of a classic save: up to 1009 records of 32 bytes
  at `0x00B734`, with the live count a u16 at `0x0009E2`.

  Field layout is from `docs/reference/kazzmir-save-layouts.md` and
  `docs/notes/2026-09-24-live-ram-evaluation.md`:

    * `+0` x (0..59)
    * `+1` y (0..39)
    * `+2` plane (0 Arcanus, 1 Myrror)
    * `+3` owner (wizard 0–4, 5 neutral)
    * `+4` max moves
    * `+5` unit type (0..197: 0–34 heroes, 35–38 ships/catapult, 39–153 racial, 154–197 summoned)
    * `+18` draw priority (used for stack display order)

  Dead units:
  Units that died during the current turn remain in the table with `plane`
  and `owner` set to `0xFF` until end-of-turn compaction. Records with
  `0xFF` or out-of-range coordinates/plane/owner/type are skipped.

  Stack collapsing and draw priority:
  The overland map shows only the top unit of a stack sharing a tile.
  *UNVERIFIED GUESS*: `+18` draw priority is the candidate field governing
  stack draw order, but its sort direction (whether higher or lower values
  appear on top) is undocumented in this repo and requires verification in
  DOSBox. We pick descending order (highest value on top), breaking ties by
  lower save-file index.
  """

  alias Mirror.SaveFile.{Cities, Sites}

  @offset 0x00B734
  @record 32
  @max 1009
  @count_offset 0x0009E2

  @type unit :: %{
          index: non_neg_integer(),
          x: non_neg_integer(),
          y: non_neg_integer(),
          plane: :arcanus | :myrror,
          owner: non_neg_integer(),
          type: non_neg_integer(),
          draw_priority: non_neg_integer()
        }

  @doc """
  Decodes the live units from a save's raw bytes into a list of unit maps.
  Returns `{:ok, units}` or `{:error, :no_units_block}` when the block cannot be read.
  """
  @spec parse(binary()) :: {:ok, [unit()]} | {:error, term()}
  def parse(<<_::binary-size(@count_offset), count::little-16, _::binary>> = raw)
      when count <= @max and byte_size(raw) >= @offset + count * @record do
    units =
      for index <- 0..(count - 1)//1,
          unit = record(binary_part(raw, @offset + index * @record, @record), index),
          unit != nil,
          do: unit

    {:ok, units}
  end

  def parse(_raw), do: {:error, :no_units_block}

  defp record(
         <<x, y, plane, owner, _max_moves, type, _::binary-size(12), draw_priority,
           _::binary-size(13)>>,
         index
       )
       when x < 60 and y < 40 and plane in [0, 1] and owner in 0..5 and type < 198 do
    %{
      index: index,
      x: x,
      y: y,
      plane: if(plane == 0, do: :arcanus, else: :myrror),
      owner: owner,
      type: type,
      draw_priority: draw_priority
    }
  end

  defp record(_bytes, _index), do: nil

  @doc """
  Selects the unit on top of a stack sharing the same tile.

  *UNVERIFIED GUESS*: The `draw_priority` field (+18) is the candidate field
  governing stack draw order, but its sort direction (whether higher or lower
  values appear on top) is undocumented in this repo and requires verification
  in DOSBox. Here we select the unit with the maximum `draw_priority` (descending),
  breaking ties by lowest index (earlier in the save table).
  """
  @spec top_of_stack([unit()]) :: unit() | nil
  def top_of_stack([]), do: nil
  def top_of_stack([unit]), do: unit

  def top_of_stack(units) when is_list(units) do
    Enum.max_by(units, fn unit -> {unit.draw_priority, -unit.index} end)
  end

  @doc """
  Collapses stacks of units on the same tile (`{x, y, plane}`) to the single
  top unit per tile, chosen by `top_of_stack/1`.
  """
  @spec collapse_stacks([unit()]) :: [unit()]
  def collapse_stacks(units) when is_list(units) do
    units
    |> Enum.group_by(fn u -> {u.x, u.y, u.plane} end)
    |> Enum.map(fn {_pos, stack} -> top_of_stack(stack) end)
    |> Enum.sort_by(& &1.index)
  end

  @doc """
  Filters out units standing on city or tower tiles.

  Cities match by `{x, y, plane}`.
  Towers stand on both planes, so they match by `{x, y}` regardless of plane.
  """
  @spec filter_visible([unit()], [map()], [map()]) :: [unit()]
  def filter_visible(units, cities, towers) when is_list(units) do
    city_tiles =
      MapSet.new(for %{x: x, y: y, plane: plane} <- cities || [], do: {x, y, plane})

    tower_tiles =
      MapSet.new(for %{x: x, y: y} <- towers || [], do: {x, y})

    Enum.reject(units, fn unit ->
      MapSet.member?(city_tiles, {unit.x, unit.y, unit.plane}) or
        MapSet.member?(tower_tiles, {unit.x, unit.y})
    end)
  end

  @doc """
  Maps a unit type (0..197) to its LBX sprite source and entry number:
  - types 0..119 -> `{:units1, type}`
  - types 120..197 -> `{:units2, type - 120}`
  Returns `nil` for any type outside 0..197.
  """
  @spec figure_sprite(integer()) ::
          {:units1, non_neg_integer()} | {:units2, non_neg_integer()} | nil
  def figure_sprite(type) when type in 0..119, do: {:units1, type}
  def figure_sprite(type) when type in 120..197, do: {:units2, type - 120}
  def figure_sprite(_type), do: nil

  @doc """
  Returns visible unit overlay items from a save's raw binary.
  Filters dead units, units garrisoned in cities or towers, collapses
  stacks, and optionally filters by plane (:arcanus or :myrror).
  Returns `[]` when `raw` is empty, too short, or lacks a valid units block.
  """
  @spec items(binary(), :arcanus | :myrror | nil, keyword()) :: [unit()]
  def items(raw, plane \\ nil, opts \\ [])

  def items(raw, plane, opts) when is_binary(raw) do
    with {:ok, units} <- parse(raw) do
      cities =
        case Keyword.fetch(opts, :cities) do
          {:ok, list} ->
            list

          :error ->
            case Cities.parse(raw) do
              {:ok, list} -> list
              _ -> []
            end
        end

      towers =
        case Keyword.fetch(opts, :towers) do
          {:ok, list} ->
            list

          :error ->
            case Sites.parse(raw) do
              {:ok, %{towers: list}} -> list
              _ -> []
            end
        end

      units =
        if plane in [:arcanus, :myrror] do
          Enum.filter(units, &(&1.plane == plane))
        else
          units
        end

      units
      |> filter_visible(cities, towers)
      |> collapse_stacks()
    else
      _ -> []
    end
  end

  def items(_raw, _plane, _opts), do: []
end
