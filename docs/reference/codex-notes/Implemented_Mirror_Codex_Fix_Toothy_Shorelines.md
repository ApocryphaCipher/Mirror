# Mirror Codex Prompt: Fix Shoreline Tile Selection (Toothy Coastlines)

## Context
Shoreline rotation is now correct, but coastlines appear overly jagged (“toothy”). Audit logs show frequent fallback from ternary shoreline masks (digits `2`) to reduced binary masks, causing blunt shoreline tiles to be overused.

This prompt focuses on **resource indexing correctness, adjacency classification, and fallback discipline**, not on reworking rotation or rendering order.

---

## Primary Findings

1. **Ternary shoreline masks are being dropped**
   - Shore tile filenames legitimately use digits `[0-2]{8}`.
   - The current resource index or lookup logic implicitly assumes binary `[0-1]{8}` masks.
   - As a result, valid tiles like `00111112.png` are never found, forcing fallback.

2. **Fallback overuse causes toothy coastlines**
   - Logs show repeated use of `reduce_diagonals_2`.
   - This collapses nuanced curved shoreline tiles into blunt cardinal-only sprites.

3. **Shore neighbors are misclassified**
   - During shoreline adjacency computation, neighbors of kind `shore` are being treated as land.
   - In Master of Magic logic, *shore is a rendering mode of ocean*, not land.
   - This produces incorrect diagonal and corner masks near coast bands.

---

## Required Changes

### 1. Fix Resource Indexing (Critical)
- Update terrain resource indexing to accept ternary shoreline keys.
- Regex **must** allow digits `0–2`:
  ```
  ^([0-2]{8})([a-e])?(?:-frame(\d+))?\.png$
  ```
- Store and index the full 8-digit key exactly as written.

### 2. Enforce 8-Digit Zero-Padded Keys
- All shoreline adjacency keys must be normalized to exactly 8 digits.
- No implicit truncation or integer-to-string loss.
- Example:
  - `11120011` ✅
  - `1110011` ❌ (invalid, will miss tiles)

### 3. Correct Adjacency Classification
When computing shoreline adjacency masks:
- Treat neighbor kinds as:
  - **Land:** grassland, desert, tundra, forest, hills, mountains, swamp, etc.
  - **Water:** ocean **and shore**
- Shore must behave as water-side for adjacency purposes.

### 4. Temporarily Disable Diagonal Reduction
- After fixing indexing and classification, disable or gate `reduce_diagonals_2`.
- This allows verification that full ternary shoreline tiles are now being selected.
- Reintroduce fallback only for genuinely missing resources.

---

## Validation Checklist

- Ternary shoreline filenames (`*2*.png`) appear in the indexed resource map.
- Lookup for `canonicalKey` succeeds without fallback.
- Coastlines visually smooth out, with fewer repetitive “teeth.”
- Fallback usage drops sharply in logs.

---

## Non-Goals
- Do not rework shoreline rotation (already correct).
- Do not redesign canonicalization unless issues persist after indexing fix.
- Do not collapse ternary logic back into binary.

---

## Outcome
After these fixes, Mirror’s shoreline selection should closely match classic MoM behavior:
- Curved coasts preserved
- Diagonal nuance retained
- Minimal fallback usage
