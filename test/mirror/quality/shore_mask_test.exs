defmodule Mirror.Quality.ShoreMaskTest do
  use ExUnit.Case, async: true

  alias Mirror.Map, as: MirrorMap
  alias Mirror.Quality.ShoreMask

  defp all_ocean_plane do
    :binary.copy(<<0::little-16>>, MirrorMap.width() * MirrorMap.height())
  end

  test "shore_mask_digits/3 marks land the same way in every direction, cardinal or diagonal" do
    terrain =
      [{0, -1}, {1, -1}, {1, 0}]
      |> Enum.reduce(all_ocean_plane(), fn {dx, dy}, acc ->
        {updated, _old} = MirrorMap.put_tile_u16_le(acc, 10 + dx, 10 + dy, 2)
        updated
      end)

    assert ShoreMask.shore_mask_digits(terrain, 10, 10) ==
             ["1", "1", "1", "0", "0", "0", "0", "0"]
  end

  test "shore_mask_digits/3 never emits the old ternary '2' for a lone diagonal land tile" do
    {terrain, _old} = MirrorMap.put_tile_u16_le(all_ocean_plane(), 11, 9, 2)

    assert ShoreMask.shore_mask_digits(terrain, 10, 10) ==
             ["0", "1", "0", "0", "0", "0", "0", "0"]
  end

  test "resolve_shore_mask_via_rules/2 reduces to a candidate that's actually available" do
    # "10100000" reduces to "11100000" under SS161EX's real rules (same
    # corner-fill logic as SS161). Only the reduced form is "available".
    candidates = ShoreMask.build_mask_candidates(["11100000"])

    resolved = ShoreMask.resolve_shore_mask_via_rules(candidates, ["1", "0", "1", "0", "0", "0", "0", "0"])

    assert resolved.mask_string == "11100000"
    assert resolved.fallback_step == "reduced"
  end

  test "resolve_shore_mask_via_rules/2 substitutes ocean's 00000000 for the degenerate all-water shore mask" do
    candidates = ShoreMask.build_mask_candidates(["00000000"])

    resolved = ShoreMask.resolve_shore_mask_via_rules(candidates, "00000000")

    assert resolved.mask_string == "00000000"
    assert resolved.fallback_step == "exact"
  end

  test "resolve_shore_mask_via_rules/2 falls through to the heuristic search when nothing else matches" do
    candidates = ShoreMask.build_mask_candidates(["10000000"])
    raw = "01000000"

    assert ShoreMask.resolve_shore_mask_via_rules(candidates, raw) ==
             ShoreMask.resolve_shore_mask(candidates, raw)
  end

  test "prefers lowest-cost nearest candidate over semantic fallback" do
    candidates = ShoreMask.build_mask_candidates(["10000000", "12000000"])
    resolved = ShoreMask.resolve_shore_mask(candidates, "11000000")

    assert resolved.mask_string == "12000000"
    assert resolved.fallback_step == "nearest_cost"
  end

  test "shore mask fallback cost favors diagonal upgrades over removals" do
    cost_remove = ShoreMask.shore_mask_fallback_cost("11000000", "10000000")
    cost_upgrade = ShoreMask.shore_mask_fallback_cost("11000000", "12000000")

    assert cost_remove.cost == 3
    assert cost_upgrade.cost == 2
  end

  test "normalize_shore_mask_digits clamps to 8 digits of 0/1/2" do
    :rand.seed(:exsplus, {101, 202, 303})

    Enum.each(1..120, fn _ ->
      mask =
        Enum.map(1..8, fn _ ->
          case :rand.uniform(5) do
            1 -> "0"
            2 -> "1"
            3 -> "2"
            4 -> "x"
            5 -> "9"
          end
        end)
        |> Enum.join()

      digits = ShoreMask.normalize_shore_mask_digits(mask)

      assert length(digits) == 8
      assert Enum.all?(digits, fn digit -> digit in ["0", "1", "2"] end)
    end)
  end

  test "cost-best selection reduces total fallback cost over semantic-first" do
    snapshot_path = Path.expand("../../fixtures/quality/shore_snapshots.json", __DIR__)
    cases = Jason.decode!(File.read!(snapshot_path))

    {baseline_cost, improved_cost} =
      Enum.reduce(cases, {0, 0}, fn case_data, {baseline_sum, improved_sum} ->
        candidates = ShoreMask.build_mask_candidates(case_data["available"] || [])
        raw = case_data["raw"]
        baseline = ShoreMask.resolve_shore_mask(candidates, raw, strategy: :semantic_first)
        improved = ShoreMask.resolve_shore_mask(candidates, raw, strategy: :cost_best)

        baseline_cost = (baseline && baseline.fallback_cost) || 0
        improved_cost = (improved && improved.fallback_cost) || 0

        {baseline_sum + baseline_cost, improved_sum + improved_cost}
      end)

    assert improved_cost < baseline_cost
  end
end
