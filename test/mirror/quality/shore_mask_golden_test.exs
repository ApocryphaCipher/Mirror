defmodule Mirror.Quality.ShoreMaskGoldenTest do
  use ExUnit.Case, async: true

  alias Mirror.Quality.ShoreMask

  @snapshot_path Path.expand("../../fixtures/quality/shore_snapshots.json", __DIR__)

  test "shore mask resolution snapshots stay stable" do
    cases = Jason.decode!(File.read!(@snapshot_path))

    Enum.each(cases, fn case_data ->
      candidates = ShoreMask.build_mask_candidates(case_data["available"] || [])
      resolved = ShoreMask.resolve_shore_mask(candidates, case_data["raw"])

      if case_data["expected_mask"] do
        assert resolved != nil
        assert resolved.mask_string == case_data["expected_mask"]
        assert resolved.fallback_step == case_data["expected_step"]
      else
        assert resolved == nil
      end
    end)
  end
end
