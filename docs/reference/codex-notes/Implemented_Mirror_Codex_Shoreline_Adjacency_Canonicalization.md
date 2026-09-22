New insights! The Adjency map is part of the tile alignment and is a vital step we are missing.

MOM does not do:
terrain → pick sprite

It does:
1. Canonical terrain kind (grass, desert, mountain, ocean)
2. Adjacency signature (8 neighbors, cardinal + diagonal)
3. Lookup sprite by (kind, adjacency signature)
4. Optional phase / animation offset

Your current pipeline is skipping step 2 or flattening it into binary → hence:
- all land becomes grass
- coast tiles rotate incorrectly
- missing shoreline tiles explode into pink “missing”

Key insight:
- Cardinals are binary (land / ocean)
- Diagonals are ternary
	- 0 = water
	- 1 = land supported by both adjacent cardinals
	- 2 = land unsupported (diagonal corner / notch)

The Adjacency state prevents ugly diagonal bridges and explains:
- why many shoreline PNG filenames contain digits 2
- why binary masks miss legitimate tiles=
- why your coastlines look rotated or jagged

How to use this immediately in Mirror
Step 1 — Formalize adjacency as data (not bits)

Instead of treating adjacency as a bitmask, define it as:

```elixir
%Adjacency{
  n: 0 | 1,
  ne: 0 | 1 | 2,
  e: 0 | 1,
  se: 0 | 1 | 2,
  s: 0 | 1,
  sw: 0 | 1 | 2,
  w: 0 | 1,
  nw: 0 | 1 | 2
}

```

This matches the PNG filenames exactly.

Step 2 — Canonicalize adjacency (this fixes rotation bugs)
Before lookup:
1. Generate all 4 rotations of the adjacency
2. Pick a canonical rotation (lexicographically smallest string)
3. Record rotation offset (0°, 90°, 180°, 270°)

This is why MOM can reuse sprites instead of storing 4 copies.
Your rotated coast bug = missing this step.


Step 3 — Build a sprite index from filenames
Those filenames like:
00011110.png
01001101.png
are already adjacency keys.

Build:
```elixir
sprites[kind][adjacency_key] = sprite
```

No guessing. No heuristics. The resources are the lookup table.

Step 4 — Use the rusty map as a validator
Overlay your computed adjacency keys and compare colors:
- If large red regions align → good
- If coastlines sparkle where expected → correct ternary logic
- If inland stays flat → correct canonicalization

This map becomes your debug oracle.

# Mirror Codex — Use Adjacency Map + Kinds Map to Fix Shoreline Rendering (MOMIME PNG Backend)

You will receive three reference images from the user:
1) A “rusty / rainbow speckle” **adjacency visualization** (encodes neighborhood signatures)
2) A **Kinds map** overlay (per-tile TerrainKind classification)
3) A **No-kinds** render (baseline)

Treat these images as ground-truth debugging aids for alignment and correctness.

## Goal
Use the adjacency visualization and the existing MOMIME terrain PNG resources to make shoreline rendering MoM-accurate by:
- modeling adjacency as first-class data
- supporting ternary diagonals for shore masks
- canonicalizing adjacency (rotation normalization)
- indexing sprites by `{plane, kind, adjacency_key, phase}`
- eliminating rotated coasts and reducing “missing” pink tiles drastically

Do NOT invent new mask encodings unless you can point to resource filenames that require them.

---

## Key Insight
MOMIME/MoM terrain PNG filenames encode adjacency keys. The resources are effectively a lookup table.

The adjacency visualization shows that the “hard cases” occur at:
- concave bays
- diagonal corners
- notches / peninsulas
These must be handled via diagonal semantics and canonicalization, not brute-force fallbacks.

---

## Requirements

### 1) Represent Adjacency Explicitly (Not As a Simple Bitmask)
Define an adjacency structure with per-direction digits:

- Cardinals (N,E,S,W): binary (0 water, 1 land)
- Diagonals (NE,SE,SW,NW): **ternary** (0,1,2)

Required direction order:
`N, NE, E, SE, S, SW, W, NW` (clockwise from north)

### 2) Ternary Diagonal Semantics for Shore Masks
For shore tiles (water tiles adjacent to land):

- Cardinal digit:
  - 1 if that neighbor is land
  - 0 if that neighbor is water

- Diagonal digit:
  - 0 if diagonal neighbor is water
  - 1 if diagonal neighbor is land AND both adjacent cardinals are land
  - 2 if diagonal neighbor is land BUT one or both adjacent cardinals are water

This is the minimal rule set that explains why some resource keys contain digit '2' on diagonals.

### 3) Canonicalize (Rotation Normalize) Adjacency Keys
MoM-style tilesets often avoid storing all 4 rotations.
Implement canonicalization:

- Generate the 4 rotated adjacency keys (0°, 90°, 180°, 270°)
- Choose a canonical representative (lexicographically smallest string is fine)
- Record rotation offset for debug display

Important:
- Do NOT rotate sprites at render time unless the resources explicitly require it.
- Primary mechanism should be canonical key lookup.

### 4) Build Sprite Index From resources-map.txt
Using `resources-map.txt`, build an index of available keys per folder:
- `{plane, kind_folder, adjacency_key, phase}` -> asset path

Support both phase naming styles:
- suffix letters `a..e`
- `-frameN`

Phase wrapping:
- `phase_effective = phase_input % frame_count_for_key`

### 5) Lookup + Fallback (Strict)
For shore rendering, lookup should be:

1) exact `{kind, adjacency_key, phase_effective}`
2) same key with frame 0
3) if missing: try canonicalized rotated keys (if not already canonical)
4) if still missing: reduce diagonals (convert diagonal 2 -> 0, then diagonal 1 -> 0) and retry
5) final fallback: `00000000` (frame 0)

Do NOT brute-force all combinations. Missing keys must be logged and treated as diagnostics.

### 6) Instrumentation (Mandatory)
Add a debug “coast audit” mode tied to hover selection that prints:
- TerrainKind at tile and neighbors
- Raw adjacency digits
- Canonical adjacency key + rotation offset
- Final key used for lookup
- File path found (or missing)
- Whether any fallback step was taken

Also output aggregate stats:
- top 20 missing adjacency keys for shore per kind folder

---

## How to Use the Supplied Images
Use the adjacency visualization to validate:
- your hotspots (coast corners) align with high-variance adjacency keys
- after fixes, adjacency hotspots should remain but “missing” tiles should drop

Use the Kinds map to validate:
- land kinds (desert/tundra/mountain) are not collapsing
- shore logic uses land-vs-water correctly per kind

Use the No-kinds render to confirm:
- “confetti” is gone
- remaining errors are only coastline/canonicalization, not terrain decoding

---

## Done Criteria
- Coastlines no longer appear rotated 90°/180° relative to landmasses
- Pink “missing” tiles are reduced dramatically (aim: >90% fewer)
- Concave bays and diagonal corners render with correct silhouettes
- Debug audit confirms diagonal=2 cases occur only on diagonals and only when cardinals do not support them

---

End of prompt.
