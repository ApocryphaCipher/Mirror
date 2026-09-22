# Mirror Codex — Terrain Phase Rendering (Updated)

## Purpose
Extend the existing terrain phase rendering system with a **static snapshot mode** that renders a single deterministic frame from animated / phased tile families.

This allows Mirror to:
- Render a stable, readable world map
- Avoid animated shimmer artifacts
- Export PNG snapshots suitable for analysis and editing

---

## Key Insight
“Sparklies” are **phase variants**, not separate data layers.

Animated terrain (water, coasts, lava, etc.) is rendered by cycling through LBX tile variants over time. A static map is produced by **freezing time** at a single phase index.

---

## Requirements

### 1. Phase Selection
Implement a phase selection mechanism:
- Global phase index (integer, default = 0)
- Optional future extension: per‑terrain‑family phase index

Example:
- Water phase = 1
- Land phase = 0
- Lava phase = 2

Initial implementation: **single global phase only**.

---

### 2. Snapshot Render Mode
Add a render mode that:
- Disables animation
- Selects exactly one tile variant per tile family
- Uses the selected phase index
- Renders one composite frame

Pipeline:
1. Decode terrain logical key (Terrain u16 + adjacency)
2. Resolve tile family + variant list
3. Select variant at `phase_index % variant_count`
4. Draw base tile
5. Draw overlays (forest, hills, dunes, lava, etc.) using same phase rule
6. Output static image

---

### 3. Export
Provide an export action:
- Name: `Export Snapshot`
- Output: PNG
- Resolution: tile_width × map_width by tile_height × map_height
- No animation, no blending across phases

---

### 4. Determinism
Snapshot output must be:
- Deterministic
- Repeatable for the same save + phase index
- Independent of render time or frame count

---

## Explicit Non‑Goals
- No animation
- No blending between phases
- No palette interpolation
- No procedural sparkle synthesis

This is a **time‑freeze**, not a new visual effect.

---

## Validation Checklist
- Water shimmer disappears
- Coastlines align correctly
- Lava/volcanic tiles render consistently
- Exported PNG matches in‑app snapshot

---

End of update.
