defmodule Mirror.Quality.SmoothingRules do
  @moduledoc """
  Real MOMIME overland-map smoothing reduction rules, ported verbatim from
  the production ruleset (`Original Master of Magic 1.31 rules.momime.xml`,
  tileSet TS01) — see docs/reference/momime-source/overland-smoothing-systems.xml.

  Each smoothing system reduces a raw per-direction bitmask down to one that
  actually has tile art. Direction numbering matches SquareMapDirection
  (N=1, NE=2, E=3, SE=4, S=5, SW=6, W=7, NW=8); `directionN` fields are
  strings of these digits (e.g. "13" = directions 1 and 3 together).
  """

  import Bitwise

  @type rule :: %{
          direction1: String.t(),
          repetitions1: integer(),
          value1: String.t(),
          direction2: String.t() | nil,
          repetitions2: integer() | nil,
          value2: String.t() | nil,
          direction3: String.t() | nil,
          repetitions3: integer() | nil,
          value3: String.t() | nil,
          set_direction1: integer(),
          set_value1: integer(),
          set_direction2: integer() | nil,
          set_value2: integer() | nil
        }

  # SS16: 16 tile set for linking together adjacent hills or mountains (maxValueEachDirection=1)
  @ss16_rules [
      %{direction1: "13", repetitions1: 2, value1: "1", direction2: nil, repetitions2: nil, value2: nil, direction3: nil, repetitions3: nil, value3: nil, set_direction1: 2, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "35", repetitions1: 2, value1: "1", direction2: nil, repetitions2: nil, value2: nil, direction3: nil, repetitions3: nil, value3: nil, set_direction1: 4, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "57", repetitions1: 2, value1: "1", direction2: nil, repetitions2: nil, value2: nil, direction3: nil, repetitions3: nil, value3: nil, set_direction1: 6, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "71", repetitions1: 2, value1: "1", direction2: nil, repetitions2: nil, value2: nil, direction3: nil, repetitions3: nil, value3: nil, set_direction1: 8, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "13", repetitions1: 2, value1: "0", direction2: nil, repetitions2: nil, value2: nil, direction3: nil, repetitions3: nil, value3: nil, set_direction1: 2, set_value1: 0, set_direction2: nil, set_value2: nil},
      %{direction1: "35", repetitions1: 2, value1: "0", direction2: nil, repetitions2: nil, value2: nil, direction3: nil, repetitions3: nil, value3: nil, set_direction1: 4, set_value1: 0, set_direction2: nil, set_value2: nil},
      %{direction1: "57", repetitions1: 2, value1: "0", direction2: nil, repetitions2: nil, value2: nil, direction3: nil, repetitions3: nil, value3: nil, set_direction1: 6, set_value1: 0, set_direction2: nil, set_value2: nil},
      %{direction1: "71", repetitions1: 2, value1: "0", direction2: nil, repetitions2: nil, value2: nil, direction3: nil, repetitions3: nil, value3: nil, set_direction1: 8, set_value1: 0, set_direction2: nil, set_value2: nil},
      %{direction1: "1", repetitions1: 1, value1: "1", direction2: "3", repetitions2: 1, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 2, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "3", repetitions1: 1, value1: "1", direction2: "5", repetitions2: 1, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 4, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "5", repetitions1: 1, value1: "1", direction2: "7", repetitions2: 1, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 6, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "7", repetitions1: 1, value1: "1", direction2: "1", repetitions2: 1, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 8, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "1", repetitions1: 1, value1: "0", direction2: "3", repetitions2: 1, value2: "1", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 2, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "3", repetitions1: 1, value1: "0", direction2: "5", repetitions2: 1, value2: "1", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 4, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "5", repetitions1: 1, value1: "0", direction2: "7", repetitions2: 1, value2: "1", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 6, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "7", repetitions1: 1, value1: "0", direction2: "1", repetitions2: 1, value2: "1", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 8, set_value1: 1, set_direction2: nil, set_value2: nil},
  ]

  # SS161: 161 tile set for converting edges of water, desert and tundra to grass to smooth edges (maxValueEachDirection=1)
  @ss161_rules [
      %{direction1: "13", repetitions1: 2, value1: "1", direction2: nil, repetitions2: nil, value2: nil, direction3: nil, repetitions3: nil, value3: nil, set_direction1: 2, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "35", repetitions1: 2, value1: "1", direction2: nil, repetitions2: nil, value2: nil, direction3: nil, repetitions3: nil, value3: nil, set_direction1: 4, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "57", repetitions1: 2, value1: "1", direction2: nil, repetitions2: nil, value2: nil, direction3: nil, repetitions3: nil, value3: nil, set_direction1: 6, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "71", repetitions1: 2, value1: "1", direction2: nil, repetitions2: nil, value2: nil, direction3: nil, repetitions3: nil, value3: nil, set_direction1: 8, set_value1: 1, set_direction2: nil, set_value2: nil},
  ]

  # SS161EX: Extended version of 161 tile set, with river mouths added (maxValueEachDirection=2)
  @ss161ex_rules [
      %{direction1: "2", repetitions1: 1, value1: "2", direction2: "2", repetitions2: 1, value2: "2", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 2, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "4", repetitions1: 1, value1: "2", direction2: "4", repetitions2: 1, value2: "2", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 4, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "6", repetitions1: 1, value1: "2", direction2: "6", repetitions2: 1, value2: "2", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 6, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "8", repetitions1: 1, value1: "2", direction2: "8", repetitions2: 1, value2: "2", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 8, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "1", repetitions1: 1, value1: "12", direction2: "3", repetitions2: 1, value2: "12", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 2, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "3", repetitions1: 1, value1: "12", direction2: "5", repetitions2: 1, value2: "12", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 4, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "5", repetitions1: 1, value1: "12", direction2: "7", repetitions2: 1, value2: "12", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 6, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "7", repetitions1: 1, value1: "12", direction2: "1", repetitions2: 1, value2: "12", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 8, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "1357", repetitions1: 0, value1: "0", direction2: "1", repetitions2: 1, value2: "2", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 3, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "1357", repetitions1: 0, value1: "0", direction2: "1", repetitions2: 1, value2: "2", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 5, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "1357", repetitions1: 0, value1: "0", direction2: "1", repetitions2: 1, value2: "2", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 7, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "1357", repetitions1: 0, value1: "0", direction2: "3", repetitions2: 1, value2: "2", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 5, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "1357", repetitions1: 0, value1: "0", direction2: "3", repetitions2: 1, value2: "2", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 7, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "1357", repetitions1: 0, value1: "0", direction2: "5", repetitions2: 1, value2: "2", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 7, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "713", repetitions1: 0, value1: "0", direction2: "5", repetitions2: 1, value2: "0", direction3: "1", repetitions3: 1, value3: "2", set_direction1: 7, set_value1: 1, set_direction2: 3, set_value2: 1},
      %{direction1: "713", repetitions1: 0, value1: "0", direction2: "5", repetitions2: 1, value2: "0", direction3: "7", repetitions3: 1, value3: "2", set_direction1: 1, set_value1: 1, set_direction2: 3, set_value2: 1},
      %{direction1: "713", repetitions1: 0, value1: "0", direction2: "5", repetitions2: 1, value2: "0", direction3: "3", repetitions3: 1, value3: "2", set_direction1: 7, set_value1: 1, set_direction2: 1, set_value2: 1},
      %{direction1: "135", repetitions1: 0, value1: "0", direction2: "7", repetitions2: 1, value2: "0", direction3: "3", repetitions3: 1, value3: "2", set_direction1: 1, set_value1: 1, set_direction2: 5, set_value2: 1},
      %{direction1: "135", repetitions1: 0, value1: "0", direction2: "7", repetitions2: 1, value2: "0", direction3: "1", repetitions3: 1, value3: "2", set_direction1: 3, set_value1: 1, set_direction2: 5, set_value2: 1},
      %{direction1: "135", repetitions1: 0, value1: "0", direction2: "7", repetitions2: 1, value2: "0", direction3: "5", repetitions3: 1, value3: "2", set_direction1: 1, set_value1: 1, set_direction2: 3, set_value2: 1},
      %{direction1: "357", repetitions1: 0, value1: "0", direction2: "1", repetitions2: 1, value2: "0", direction3: "5", repetitions3: 1, value3: "2", set_direction1: 3, set_value1: 1, set_direction2: 7, set_value2: 1},
      %{direction1: "357", repetitions1: 0, value1: "0", direction2: "1", repetitions2: 1, value2: "0", direction3: "3", repetitions3: 1, value3: "2", set_direction1: 5, set_value1: 1, set_direction2: 7, set_value2: 1},
      %{direction1: "357", repetitions1: 0, value1: "0", direction2: "1", repetitions2: 1, value2: "0", direction3: "7", repetitions3: 1, value3: "2", set_direction1: 3, set_value1: 1, set_direction2: 5, set_value2: 1},
      %{direction1: "571", repetitions1: 0, value1: "0", direction2: "3", repetitions2: 1, value2: "0", direction3: "7", repetitions3: 1, value3: "2", set_direction1: 5, set_value1: 1, set_direction2: 1, set_value2: 1},
      %{direction1: "571", repetitions1: 0, value1: "0", direction2: "3", repetitions2: 1, value2: "0", direction3: "5", repetitions3: 1, value3: "2", set_direction1: 7, set_value1: 1, set_direction2: 1, set_value2: 1},
      %{direction1: "571", repetitions1: 0, value1: "0", direction2: "3", repetitions2: 1, value2: "0", direction3: "1", repetitions3: 1, value3: "2", set_direction1: 5, set_value1: 1, set_direction2: 7, set_value2: 1},
      %{direction1: "15", repetitions1: 2, value1: "0", direction2: "37", repetitions2: 0, value2: "0", direction3: "3", repetitions3: 1, value3: "2", set_direction1: 7, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "15", repetitions1: 2, value1: "0", direction2: "37", repetitions2: 0, value2: "0", direction3: "7", repetitions3: 1, value3: "2", set_direction1: 3, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "37", repetitions1: 2, value1: "0", direction2: "15", repetitions2: 0, value2: "0", direction3: "1", repetitions3: 1, value3: "2", set_direction1: 5, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "37", repetitions1: 2, value1: "0", direction2: "15", repetitions2: 0, value2: "0", direction3: "5", repetitions3: 1, value3: "2", set_direction1: 1, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "136", repetitions1: 0, value1: "0", direction2: "57", repetitions2: 2, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 1, set_value1: 1, set_direction2: 3, set_value2: 1},
      %{direction1: "358", repetitions1: 0, value1: "0", direction2: "17", repetitions2: 2, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 3, set_value1: 1, set_direction2: 5, set_value2: 1},
      %{direction1: "572", repetitions1: 0, value1: "0", direction2: "13", repetitions2: 2, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 5, set_value1: 1, set_direction2: 7, set_value2: 1},
      %{direction1: "714", repetitions1: 0, value1: "0", direction2: "35", repetitions2: 2, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 7, set_value1: 1, set_direction2: 1, set_value2: 1},
      %{direction1: "14", repetitions1: 0, value1: "0", direction2: "357", repetitions2: 3, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 1, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "16", repetitions1: 0, value1: "0", direction2: "357", repetitions2: 3, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 1, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "36", repetitions1: 0, value1: "0", direction2: "157", repetitions2: 3, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 3, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "38", repetitions1: 0, value1: "0", direction2: "157", repetitions2: 3, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 3, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "58", repetitions1: 0, value1: "0", direction2: "137", repetitions2: 3, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 5, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "52", repetitions1: 0, value1: "0", direction2: "137", repetitions2: 3, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 5, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "72", repetitions1: 0, value1: "0", direction2: "135", repetitions2: 3, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 7, set_value1: 1, set_direction2: nil, set_value2: nil},
      %{direction1: "74", repetitions1: 0, value1: "0", direction2: "135", repetitions2: 3, value2: "0", direction3: nil, repetitions3: nil, value3: nil, set_direction1: 7, set_value1: 1, set_direction2: nil, set_value2: nil},
  ]

  @max_value %{"SS16" => 1, "SS161" => 1, "SS161EX" => 2}

  @doc "Rules for a given smoothing system ID."
  def rules("SS16"), do: @ss16_rules
  def rules("SS161"), do: @ss161_rules
  def rules("SS161EX"), do: @ss161ex_rules

  @doc "Max digit value for each direction under a given smoothing system (1 = binary, 2 = ternary)."
  def max_value(system_id), do: Map.fetch!(@max_value, system_id)

  @doc """
  Reduces a raw 8-digit mask string down to one that has real tile art,
  applying every rule for `system_id` in order (each rule sees the previous
  rules' output — matches `SmoothingSystemEx.applySmoothingReductionRules`).
  """
  @spec reduce_mask(String.t(), String.t()) :: String.t()
  def reduce_mask(mask, system_id) do
    system_id
    |> rules()
    |> Enum.reduce(mask, &apply_rule/2)
  end

  @doc """
  Precomputes the full raw-mask -> reduced-mask table for every binary (0/1)
  8-digit combination under `system_id` — 256 entries. Cheap (a few hundred
  rule applications total) and lets callers (including the JS client, via
  the atlas payload) do a plain lookup instead of re-running the rules per
  tile.
  """
  @spec build_lookup(String.t()) :: %{String.t() => String.t()}
  def build_lookup(system_id) do
    for n <- 0..255, into: %{} do
      raw =
        for bit <- 7..0//-1 do
          if (n &&& 1 <<< bit) != 0, do: "1", else: "0"
        end
        |> Enum.join()

      {raw, reduce_mask(raw, system_id)}
    end
  end

  defp apply_rule(rule, mask) do
    if condition_matches?(mask, rule.direction1, rule.repetitions1, rule.value1) &&
         condition_matches?(mask, rule.direction2, rule.repetitions2, rule.value2) &&
         condition_matches?(mask, rule.direction3, rule.repetitions3, rule.value3) do
      mask
      |> apply_replacement(rule.set_direction1, rule.set_value1)
      |> apply_replacement(rule.set_direction2, rule.set_value2)
    else
      mask
    end
  end

  defp condition_matches?(_mask, nil, nil, nil), do: true

  defp condition_matches?(mask, directions, repetitions, value) do
    count =
      directions
      |> String.graphemes()
      |> Enum.count(fn direction_digit ->
        index = String.to_integer(direction_digit) - 1
        digit = String.at(mask, index)
        String.contains?(value, digit)
      end)

    count == repetitions
  end

  defp apply_replacement(mask, nil, nil), do: mask

  defp apply_replacement(mask, direction, value) do
    index = direction - 1
    String.slice(mask, 0, index) <> Integer.to_string(value) <> String.slice(mask, (index + 1)..-1//1)
  end
end
