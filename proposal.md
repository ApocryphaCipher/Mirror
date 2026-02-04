# Proposal: Normalize Map.wrap_x for large negative inputs

## Discovery (Read-Only)
- No Fatecarver discoveries found in repo.
- `Mirror.Map.wrap_x/1` uses `rem(x + @width * 1000, @width)` for negative values.
- For x < `-@width * 1000`, this returns negative results (e.g. `-1`), which breaks the
  “always in bounds” invariant.

## What
- Replace negative handling in `Mirror.Map.wrap_x/1` with `Integer.mod/2` for any integer input.
- Add a focused unit test covering large negative inputs.

## Why
- Guarantees wrap results are always in `0..(@width - 1)` for any integer.
- Prevents out-of-bounds indices if callers ever pass large negative coordinates.

## Metrics (Before/After)
| Metric | Before | After |
| --- | --- | --- |
| In-bounds results on sample set `[-1, width, width+5, -(width*1000+1)]` | 3/4 | 4/4 |
| `wrap_x/1` unit test coverage | 0 tests | 1 test |

## Tests
- Command: `mix test test/mirror/map_test.exs`
- Expectation: Fails on old behavior due to large negative case, passes after fix.

## Determinism
- `wrap_x/1` remains a pure, deterministic function.

## Risks
- Low: only changes wrapping logic for negative values, which is more correct for any integer input.

## Rollback
- Revert `lib/mirror/map.ex` and remove `test/mirror/map_test.exs`.
