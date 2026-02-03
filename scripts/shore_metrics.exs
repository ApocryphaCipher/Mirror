alias Mirror.Quality.ShoreMask

snapshot_path = Path.expand("../test/fixtures/quality/shore_snapshots.json", __DIR__)
cases = Jason.decode!(File.read!(snapshot_path))

merge_metrics = fn acc, metrics ->
  %{
    total: acc.total + metrics.total,
    fallback_applied: acc.fallback_applied + metrics.fallback_applied,
    cost_sum: acc.cost_sum + metrics.cost_sum,
    semantic_mismatch: acc.semantic_mismatch + metrics.semantic_mismatch
  }
end

{baseline, improved} =
  Enum.reduce(
    cases,
    {%{total: 0, fallback_applied: 0, cost_sum: 0, semantic_mismatch: 0},
     %{total: 0, fallback_applied: 0, cost_sum: 0, semantic_mismatch: 0}},
    fn case_data, {baseline_acc, improved_acc} ->
      candidates = ShoreMask.build_mask_candidates(case_data["available"] || [])
      raw = case_data["raw"]

      baseline_metrics = ShoreMask.shore_mask_metrics([raw], candidates, strategy: :semantic_first)
      improved_metrics = ShoreMask.shore_mask_metrics([raw], candidates, strategy: :cost_best)

      {merge_metrics.(baseline_acc, baseline_metrics),
       merge_metrics.(improved_acc, improved_metrics)}
    end
  )

output = %{baseline: baseline, improved: improved}
IO.puts(Jason.encode!(output, pretty: true))
