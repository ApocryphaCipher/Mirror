# Mirror Codex — Phase Loop Length (Auto-Detect via Pixel-Diff Convergence)

## Goal
Do NOT hard-code a phase loop length (8/16/etc). Instead, **auto-detect** the loop period for the current render configuration using **pixel-diff convergence** on successive snapshot frames.

---

## Why
Different tile families and render pipelines may have different phase counts (e.g., water vs lava).
Hard-coding a loop length makes the phase picker misleading and breaks snapshot determinism across saves/asset sets.

---

## Required Behavior

### 1) Provide an Auto-Detect Action
Add a UI action/button or internal startup step:
- `Detect Phase Loop`
- Outputs detected `loop_len` (integer >= 1)
- Stores `loop_len` in state for:
  - phase picker wrap/clamp
  - snapshot export determinism

### 2) Detection Algorithm (Pixel-Diff Convergence)
Render a sequence of snapshot frames at phase indices starting from 0:

- Let `img(p)` be the rendered full-map snapshot at phase `p`.
- Compute `diff(img(a), img(b))` as a cheap per-pixel difference metric.
  - Acceptable: sum(|RGBAa - RGBAb|) across pixels, or hash-based comparison.
  - Prefer speed: use a fast hash (xxhash/sha) over raw RGBA bytes.

Detect the smallest loop length `L` such that:
- `img(0)` is “equal” to `img(L)` under a strict threshold

Implementation details:
- Generate up to `max_phases` frames (start with 32).
- For each p from 1..max_phases:
  - compute `d = diff(img(0), img(p))`
  - if `d <= threshold`: candidate loop length = p; stop

Threshold guidance:
- Prefer **exact match** if rendering is deterministic (best).
- If minor noise occurs (antialiasing, scaling), allow a tiny threshold.
  - Ensure canvas geometry invariants are enforced so exact matches are feasible.

If no match within `max_phases`:
- fall back to `loop_len = 8` and mark as “unknown/assumed” in UI.

### 3) Determinism Requirements
- Ensure the render pipeline is deterministic for a given phase:
  - no time-based randomness
  - no accumulated transforms
  - fixed palette selection
  - fixed tile size / DPR buffer sizing

### 4) Apply Detected Loop Length
- Clamp/wrap phase picker:
  - `effective_phase = phase_input % loop_len`
- Snapshot export uses `effective_phase` and reports:
  - `phase_input`, `effective_phase`, `loop_len`

---

## Optional Enhancement (Per-Family Loop)
If/when tile families are rendered separately, allow:
- global loop detection (full-map)
- per-family detection (water-only mask or family-filtered render)
Store as:
- `loop_len_global`
- `loop_len_by_family`

Not required for initial implementation.

---

## Validation Checklist
- Phase picker stops “going to infinity” in effect.
- Phase 0..(loop_len-1) cycles visually; phase == loop_len matches phase 0.
- Exported snapshots at phase 0 and phase loop_len are identical (or within threshold).
- Detected loop_len is stable across runs for same save + assets.

---

End of document.
