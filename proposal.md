# Proposal — Shoreline Mask Quality Pass (Deterministic Fallback Selection)

## Target Subsystem
Momime PNG shoreline mask selection in `assets/js/map_hooks.js` with a matching quality harness in `lib/mirror/quality/shore_mask.ex`.

## Metrics (2–3)
1. **Shore fallback applied count**: number of shore masks that require any fallback.
2. **Fallback cost sum**: total penalty for chosen fallbacks (lower is better).
3. **Semantic mismatch count**: fallbacks that cross shoreline semantic classes (should be 0).

## Benchmark Fixtures (8)
Shoreline mask cases captured in `test/fixtures/quality/shore_snapshots.json`:
`exact_match`, `canonical_match`, `semantic_fallback`, `nearest_beats_semantic`,
`nearest_only`, `fallback_zero`, `missing`, `canonical_from_semantic_variant`.

## Test Plan
Unit tests:
- Fallback cost scoring prioritization.
- Fallback selection prefers lowest-cost nearest candidate when better than semantic fallback.

Property/fuzz tests:
- Mask normalization invariants (8 digits, only 0/1/2).

Golden tests:
- Snapshot of resolution outcomes for the 8 fixtures in `test/fixtures/quality/shore_snapshots.json`.

## Implementation Plan
1. Add a small quality module (`Mirror.Quality.ShoreMask`) mirroring shore mask logic for tests/metrics.
2. Update `resolveMomimePathForShore` to score semantic fallback candidates and the nearest available mask, then pick the lowest-cost option deterministically.
3. Keep determinism via stable tie-breakers (cost, cardinal flips, mask string).

## Rollback Strategy
Revert the `resolveMomimePathForShore` selection change and remove the quality module/tests.

## Performance Notes
Candidate scoring is bounded by a small set of masks per tile and runs only when exact/canonical matches fail. The path resolution calls remain unchanged.
