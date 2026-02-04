defmodule Mirror.Quality.ShoreMask do
  @moduledoc """
  Shoreline mask helpers for quality metrics and deterministic selection.
  """

  import Bitwise

  alias Mirror.Map, as: MirrorMap

  @dirs [
    {0, -1},
    {1, -1},
    {1, 0},
    {1, 1},
    {0, 1},
    {-1, 1},
    {-1, 0},
    {-1, -1}
  ]

  @terrain_kind_by_base_id %{
    0 => :ocean,
    1 => :shore,
    2 => :grass,
    3 => :forest,
    4 => :hill,
    5 => :mountain,
    6 => :tundra,
    7 => :swamp,
    8 => :desert,
    9 => :grass,
    10 => :forest,
    11 => :hill,
    12 => :mountain,
    13 => :tundra,
    14 => :swamp,
    15 => :desert
  }

  @diag_indices [1, 3, 5, 7]
  @diag_labels %{1 => "ne", 3 => "se", 5 => "sw", 7 => "nw"}

  def terrain_base_kind_for_value(value) when is_integer(value) do
    base = value &&& 0xFF
    Map.get(@terrain_kind_by_base_id, base, :unknown)
  end

  def terrain_base_kind_for_value(_value), do: :unknown

  def terrain_base_kind_at(terrain_bin, x, y) do
    terrain_bin
    |> MirrorMap.get_tile_u16_le(x, y)
    |> terrain_base_kind_for_value()
  end

  def terrain_kind_at(terrain_bin, x, y) do
    base_kind = terrain_base_kind_at(terrain_bin, x, y)

    cond do
      base_kind in [:ocean, :shore] ->
        base_kind

      adjacent_to_ocean?(terrain_bin, x, y) ->
        :shore

      true ->
        base_kind
    end
  end

  def shore_mask_digits(terrain_bin, x, y) do
    land =
      Enum.map(@dirs, fn {dx, dy} ->
        nx = MirrorMap.wrap_x(x + dx)
        ny = MirrorMap.clamp_y(y + dy)

        case ny do
          :off ->
            false

          _ ->
            kind = terrain_base_kind_at(terrain_bin, nx, ny)
            not water_kind?(kind)
        end
      end)

    Enum.with_index(land)
    |> Enum.map(fn {is_land, idx} ->
      if rem(idx, 2) == 0 do
        if is_land, do: "1", else: "0"
      else
        left = Enum.at(land, rem(idx + 7, 8))
        right = Enum.at(land, rem(idx + 1, 8))

        cond do
          left && right -> "1"
          is_land -> "2"
          true -> "0"
        end
      end
    end)
  end

  def normalize_mask_string(mask_string) do
    String.pad_leading(to_string(mask_string || ""), 8, "0")
    |> String.slice(0, 8)
  end

  def mask_string_from_digits(digits) when is_list(digits), do: Enum.join(digits)
  def mask_string_from_digits(digits), do: to_string(digits || "")

  def normalize_shore_mask_digits(mask_digits) when is_list(mask_digits) do
    digits =
      mask_digits
      |> Enum.map(&to_string/1)
      |> Enum.take(8)

    digits
    |> pad_digits()
    |> Enum.map(fn value -> if value in ["1", "2"], do: value, else: "0" end)
  end

  def normalize_shore_mask_digits(mask_digits) do
    normalize_mask_string(mask_digits)
    |> String.graphemes()
    |> Enum.map(fn value -> if value in ["1", "2"], do: value, else: "0" end)
  end

  def classify_shore_semantics(mask_digits) do
    digits = normalize_shore_mask_digits(mask_digits)

    cardinal_digits = [
      Enum.at(digits, 0),
      Enum.at(digits, 2),
      Enum.at(digits, 4),
      Enum.at(digits, 6)
    ]

    cardinal_land = Enum.map(cardinal_digits, fn value -> value != "0" end)
    water_indices = cardinal_land |> Enum.with_index() |> Enum.filter(fn {land?, _} -> !land? end)
    water_indices = Enum.map(water_indices, fn {_land?, index} -> index end)
    water_count = length(water_indices)

    diagonal_water =
      [Enum.at(digits, 1), Enum.at(digits, 3), Enum.at(digits, 5), Enum.at(digits, 7)]
      |> Enum.any?(fn value -> value == "0" end)

    {semantic, corner_diagonal} =
      cond do
        water_count == 0 ->
          if diagonal_water, do: {"convex_corner", nil}, else: {"straight_edge", nil}

        water_count == 1 ->
          {"straight_edge", nil}

        water_count == 2 ->
          [a, b] = water_indices

          if !cardinal_adjacent?(a, b) do
            {"channel", nil}
          else
            corner = corner_diagonal_for_cardinals(a, b)
            diag_digit = if corner == nil, do: "0", else: Enum.at(digits, corner) || "0"
            if diag_digit != "0", do: {"concave_inlet", corner}, else: {"convex_corner", corner}
          end

        water_count == 3 ->
          {"peninsula", nil}

        water_count == 4 ->
          {"island_tip", nil}

        true ->
          {"straight_edge", nil}
      end

    %{
      class: semantic,
      water_count: water_count,
      water_indices: water_indices,
      corner_diagonal: corner_diagonal,
      digits: digits
    }
  end

  def shore_semantic_fallbacks(mask_string, semantic_class) do
    normalized = normalize_mask_string(mask_string)
    base_digits = String.graphemes(normalized)

    {variants, seen} =
      Enum.reduce(@diag_indices, {[], MapSet.new([normalized])}, fn index, {acc, seen} ->
        if Enum.at(base_digits, index) == "2" do
          next = List.replace_at(base_digits, index, "1")

          push_variant(
            next,
            "relax_diag_2_to_1_#{@diag_labels[index]}",
            semantic_class,
            acc,
            seen
          )
        else
          {acc, seen}
        end
      end)

    {variants, seen} =
      Enum.reduce(@diag_indices, {variants, seen}, fn index, {acc, seen} ->
        if Enum.at(base_digits, index) == "2" do
          next = List.replace_at(base_digits, index, "0")

          push_variant(
            next,
            "relax_diag_2_to_0_#{@diag_labels[index]}",
            semantic_class,
            acc,
            seen
          )
        else
          {acc, seen}
        end
      end)

    {variants, seen} =
      Enum.reduce(@diag_indices, {variants, seen}, fn index, {acc, seen} ->
        if Enum.at(base_digits, index) == "1" do
          next = List.replace_at(base_digits, index, "0")

          push_variant(
            next,
            "relax_diag_1_to_0_#{@diag_labels[index]}",
            semantic_class,
            acc,
            seen
          )
        else
          {acc, seen}
        end
      end)

    reduced_2_to_1 = reduce_diagonal_mask_string(normalized, "2", "1")

    {variants, seen} =
      if reduced_2_to_1 != normalized do
        push_variant(
          String.graphemes(reduced_2_to_1),
          "relax_diagonals_2_to_1",
          semantic_class,
          variants,
          seen
        )
      else
        {variants, seen}
      end

    reduced_2_to_0 = reduce_diagonal_mask_string(normalized, "2", "0")

    {variants, seen} =
      if reduced_2_to_0 != normalized do
        push_variant(
          String.graphemes(reduced_2_to_0),
          "relax_diagonals_2_to_0",
          semantic_class,
          variants,
          seen
        )
      else
        {variants, seen}
      end

    reduced_1_to_0 = reduce_diagonal_mask_string(normalized, "1", "0")

    {variants, _seen} =
      if reduced_1_to_0 != normalized do
        push_variant(
          String.graphemes(reduced_1_to_0),
          "relax_diagonals_1_to_0",
          semantic_class,
          variants,
          seen
        )
      else
        {variants, seen}
      end

    variants
  end

  def rotate_mask_string(mask_string, shift) do
    digits = normalize_mask_string(mask_string) |> String.graphemes()
    rotate_mask_digits(digits, shift) |> Enum.join()
  end

  def mask_rotations(mask_string) do
    normalized = normalize_mask_string(mask_string)

    rotations = [
      %{mask_string: normalized, rotation: 0, shift: 0},
      %{mask_string: rotate_mask_string(normalized, 2), rotation: 90, shift: 2},
      %{mask_string: rotate_mask_string(normalized, 4), rotation: 180, shift: 4},
      %{mask_string: rotate_mask_string(normalized, 6), rotation: 270, shift: 6}
    ]

    Enum.reduce(rotations, {[], MapSet.new()}, fn entry, {acc, seen} ->
      if MapSet.member?(seen, entry.mask_string) do
        {acc, seen}
      else
        {[entry | acc], MapSet.put(seen, entry.mask_string)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  def canonical_mask_string(mask_string) do
    rotations = mask_rotations(mask_string)
    default = %{mask_string: normalize_mask_string(mask_string), rotation: 0}

    Enum.reduce(rotations, default, fn entry, best ->
      if entry.mask_string < best.mask_string, do: entry, else: best
    end)
  end

  def reduce_diagonal_mask_string(mask_string, from_digit, to_digit) do
    digits = normalize_mask_string(mask_string) |> String.graphemes()

    @diag_indices
    |> Enum.reduce(digits, fn index, acc ->
      if Enum.at(acc, index) == from_digit do
        List.replace_at(acc, index, to_digit)
      else
        acc
      end
    end)
    |> Enum.join()
  end

  def shore_mask_fallback_cost(source_digits, target_digits) do
    source = normalize_shore_mask_digits(source_digits)
    target = normalize_shore_mask_digits(target_digits)

    Enum.reduce(0..7, %{cost: 0, cardinal_flips: 0, bit_flips: List.duplicate(0, 8)}, fn index,
                                                                                         acc ->
      a = Enum.at(source, index)
      b = Enum.at(target, index)

      if a == b do
        acc
      else
        bit_flips = List.update_at(acc.bit_flips, index, &(&1 + 1))

        if rem(index, 2) == 0 do
          %{
            acc
            | cost: acc.cost + 10,
              cardinal_flips: acc.cardinal_flips + 1,
              bit_flips: bit_flips
          }
        else
          pair = a <> b
          delta = if pair in ["12", "21"], do: 2, else: 3
          %{acc | cost: acc.cost + delta, bit_flips: bit_flips}
        end
      end
    end)
  end

  def build_mask_candidates(mask_strings) do
    all = MapSet.new(mask_strings || [])

    by_semantic =
      mask_strings
      |> Enum.reduce(%{}, fn mask, acc ->
        semantic = classify_shore_semantics(mask).class
        Map.update(acc, semantic, [mask], fn list -> [mask | list] end)
      end)
      |> Enum.into(%{}, fn {semantic, masks} ->
        {semantic, masks |> Enum.uniq() |> Enum.sort()}
      end)

    %{all: all, by_semantic: by_semantic}
  end

  def resolve_shore_mask(candidates, mask_digits, opts \\ []) do
    diagonal_reduction? = Keyword.get(opts, :diagonal_reduction, true)
    strategy = Keyword.get(opts, :strategy, :cost_best)
    raw_mask = normalize_mask_string(mask_string_from_digits(mask_digits))
    semantic = classify_shore_semantics(mask_digits)
    semantic_class = semantic.class
    canonical = canonical_mask_string(raw_mask)

    if mask_available?(candidates, raw_mask) do
      %{
        mask_string: raw_mask,
        rotation: 0,
        fallback_step: "exact",
        fallback_applied: false,
        fallback_cost: 0,
        fallback_cardinal_flips: 0,
        semantic_class: semantic_class
      }
    else
      if canonical.mask_string != raw_mask && mask_available?(candidates, canonical.mask_string) do
        %{
          mask_string: canonical.mask_string,
          rotation: canonical.rotation,
          fallback_step: "canonical",
          fallback_applied: true,
          fallback_cost: 0,
          fallback_cardinal_flips: 0,
          semantic_class: semantic_class
        }
      else
        raw_digits = normalize_shore_mask_digits(mask_digits)

        semantic_best =
          cond do
            !diagonal_reduction? ->
              nil

            strategy == :semantic_first ->
              first_semantic_fallback(candidates, raw_mask, raw_digits, semantic_class)

            true ->
              best_semantic_fallback(candidates, raw_mask, raw_digits, semantic_class)
          end

        nearest =
          case strategy do
            :semantic_first ->
              if semantic_best,
                do: nil,
                else: nearest_shore_mask(candidates, semantic_class, raw_digits)

            _ ->
              nearest_shore_mask(candidates, semantic_class, raw_digits)
          end

        best =
          case strategy do
            :semantic_first -> semantic_best || nearest
            _ -> pick_best_candidate([semantic_best, nearest])
          end

        cond do
          best ->
            %{
              mask_string: best.mask_string,
              rotation: best.rotation,
              fallback_step: best.step,
              fallback_applied: true,
              fallback_cost: best.cost,
              fallback_cardinal_flips: best.cardinal_flips,
              semantic_class: semantic_class
            }

          mask_available?(candidates, "00000000") ->
            %{
              mask_string: "00000000",
              rotation: 0,
              fallback_step: "fallback_zero",
              fallback_applied: true,
              fallback_cost: 0,
              fallback_cardinal_flips: 0,
              semantic_class: semantic_class
            }

          true ->
            nil
        end
      end
    end
  end

  def shore_mask_metrics(mask_cases, candidates, opts \\ []) when is_list(mask_cases) do
    Enum.reduce(
      mask_cases,
      %{total: 0, fallback_applied: 0, cost_sum: 0, semantic_mismatch: 0},
      fn mask, acc ->
        resolved = resolve_shore_mask(candidates, mask, opts)
        acc = %{acc | total: acc.total + 1}
        semantic_class = classify_shore_semantics(mask).class

        cond do
          resolved == nil ->
            %{
              acc
              | fallback_applied: acc.fallback_applied + 1,
                semantic_mismatch: acc.semantic_mismatch + 1
            }

          resolved.fallback_applied ->
            resolved_class = classify_shore_semantics(resolved.mask_string).class
            mismatch = if resolved_class != semantic_class, do: 1, else: 0

            %{
              acc
              | fallback_applied: acc.fallback_applied + 1,
                cost_sum: acc.cost_sum + (resolved.fallback_cost || 0),
                semantic_mismatch: acc.semantic_mismatch + mismatch
            }

          true ->
            acc
        end
      end
    )
  end

  defp adjacent_to_ocean?(terrain_bin, x, y) do
    Enum.any?(@dirs, fn {dx, dy} ->
      nx = MirrorMap.wrap_x(x + dx)
      ny = MirrorMap.clamp_y(y + dy)

      case ny do
        :off ->
          false

        _ ->
          terrain_base_kind_at(terrain_bin, nx, ny) == :ocean
      end
    end)
  end

  defp water_kind?(kind), do: kind in [:ocean, :shore]

  defp pad_digits(digits) when length(digits) < 8, do: pad_digits(digits ++ ["0"])
  defp pad_digits(digits), do: Enum.take(digits, 8)

  defp cardinal_adjacent?(a, b), do: rem(a + 1, 4) == b || rem(b + 1, 4) == a

  defp corner_diagonal_for_cardinals(a, b) do
    min = min(a, b)
    max = max(a, b)

    cond do
      min == 0 && max == 1 -> 1
      min == 1 && max == 2 -> 3
      min == 2 && max == 3 -> 5
      min == 0 && max == 3 -> 7
      true -> nil
    end
  end

  defp rotate_mask_digits(digits, shift) do
    list = if is_list(digits), do: digits, else: []
    offset = rem(shift, 8)
    offset = if offset < 0, do: offset + 8, else: offset

    if offset == 0 do
      Enum.take(list, 8)
    else
      Enum.reduce(0..7, List.duplicate("0", 8), fn index, acc ->
        value = Enum.at(list, index) || "0"
        List.replace_at(acc, rem(index + offset, 8), value)
      end)
    end
  end

  defp push_variant(digits, step, semantic_class, acc, seen) do
    candidate = Enum.join(digits)

    cond do
      MapSet.member?(seen, candidate) ->
        {acc, seen}

      classify_shore_semantics(candidate).class != semantic_class ->
        {acc, seen}

      true ->
        {acc ++ [{candidate, step}], MapSet.put(seen, candidate)}
    end
  end

  defp mask_available?(candidates, mask_string) do
    MapSet.member?(candidates.all, normalize_mask_string(mask_string))
  end

  defp best_semantic_fallback(candidates, raw_mask, raw_digits, semantic_class) do
    variants = shore_semantic_fallbacks(raw_mask, semantic_class)

    {options, _seen} =
      Enum.reduce(variants, {[], MapSet.new()}, fn {mask_string, step}, {acc, seen} ->
        {acc, seen} =
          maybe_add_candidate(candidates, mask_string, 0, step, raw_digits, acc, seen)

        canonical = canonical_mask_string(mask_string)

        if canonical.mask_string != mask_string do
          maybe_add_candidate(
            candidates,
            canonical.mask_string,
            canonical.rotation,
            step,
            raw_digits,
            acc,
            seen
          )
        else
          {acc, seen}
        end
      end)

    pick_best_candidate(options)
  end

  defp first_semantic_fallback(candidates, raw_mask, raw_digits, semantic_class) do
    variants = shore_semantic_fallbacks(raw_mask, semantic_class)

    Enum.find_value(variants, fn {mask_string, step} ->
      normalized = normalize_mask_string(mask_string)

      cond do
        mask_available?(candidates, normalized) ->
          candidate_from_mask(raw_digits, normalized, 0, step)

        true ->
          canonical = canonical_mask_string(normalized)

          if canonical.mask_string != normalized &&
               mask_available?(candidates, canonical.mask_string) do
            candidate_from_mask(raw_digits, canonical.mask_string, canonical.rotation, step)
          else
            nil
          end
      end
    end)
  end

  defp maybe_add_candidate(candidates, mask_string, rotation, step, raw_digits, acc, seen) do
    normalized = normalize_mask_string(mask_string)

    cond do
      MapSet.member?(seen, normalized) ->
        {acc, seen}

      !mask_available?(candidates, normalized) ->
        {acc, MapSet.put(seen, normalized)}

      true ->
        candidate = candidate_from_mask(raw_digits, normalized, rotation, step)
        {[candidate | acc], MapSet.put(seen, normalized)}
    end
  end

  defp nearest_shore_mask(candidates, semantic_class, raw_digits) do
    masks = Map.get(candidates.by_semantic, semantic_class, [])

    masks
    |> Enum.map(fn mask -> candidate_from_mask(raw_digits, mask, 0, "nearest_cost") end)
    |> pick_best_candidate()
  end

  defp pick_best_candidate(candidates) do
    filtered = Enum.reject(candidates, &is_nil/1)

    case filtered do
      [] ->
        nil

      [first | rest] ->
        Enum.reduce(rest, first, fn candidate, best ->
          cond do
            candidate.cost < best.cost ->
              candidate

            candidate.cost == best.cost && candidate.cardinal_flips < best.cardinal_flips ->
              candidate

            candidate.cost == best.cost && candidate.cardinal_flips == best.cardinal_flips &&
                candidate.mask_string < best.mask_string ->
              candidate

            true ->
              best
          end
        end)
    end
  end

  defp candidate_from_mask(raw_digits, mask_string, rotation, step) do
    cost = shore_mask_fallback_cost(raw_digits, mask_string)

    %{
      mask_string: normalize_mask_string(mask_string),
      rotation: rotation,
      step: step,
      cost: cost.cost,
      cardinal_flips: cost.cardinal_flips
    }
  end
end
