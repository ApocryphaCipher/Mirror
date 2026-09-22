# Mirror Codex — Render MOMIME Terrain PNG Tiles (Project-Local Resources)

## Goal
Render terrain tiles using the MOMIME-extracted PNG files located inside the Mirror project directory:

- `resources/momime.client.graphics/overland/terrain/arcanus`
- `resources/momime.client.graphics/overland/terrain/myrror`

Do **not** require `MIRROR_MOMIME_RES_PATH`. Assume these resources are copied into the repo.

---

## Resource Naming Convention (Must Support)

Files are organized by:
- plane: `arcanus` | `myrror`
- terrain kind folder: `ocean`, `shore`, `desert`, `grasslands`, `forest`, `hills`, `mountains`, `tundra`, `swamp`, etc.
- filename encodes adjacency mask and optional phase frame.

Examples:
- `desert/00111111.png`
- `desert/00000000a.png` (phase suffix a/b/c/d)
- `shore/00001110-frame1.png` (explicit frame naming)
- `ocean/00000000e.png` (ocean has a..e variants)
- `river/11000111c.png` (mask + phase suffix)

The `resources-map.txt` file enumerates all available files and should be used to build an index at runtime (or compile-time).

---

## Required Implementation

### 1) Add a Sprite Backend: `:momime_png`
Add a renderer backend selection:
- Prefer `:momime_png` if project-local resources exist.
- Fall back to LBX only if resources are missing.

### 2) Build an Index from resources-map.txt
At app start (or first render), build an in-memory index.

Key:
- `{plane, terrain_kind, mask_string, frame}`

Value:
- relative path to PNG under `resources/momime.client.graphics/overland/terrain/...`

Where:
- `mask_string` is the leading token in the filename (keep as string)
- `frame` is:
  - integer (1..N) for `-frameN`
  - letter (`"a".."e"`) for suffix variants
  - `0` for no frame specified (static)

Index must support:
- lookup by exact frame if available
- fallback to frame 0 if frame not available
- wrapping phase modulo available frames for that key

### 3) Resolve Tile Image for Each Map Cell
For base terrain rendering, compute:
- `plane` from viewer (`:arcanus`/`:myrror`)
- `terrain_kind` from your normalization logic
- `mask_string` from adjacency mask:
  - convert `adj_mask` (0..255) into 8-bit binary string with leading zeros (e.g., 0 -> `00000000`, 63 -> `00111111`)
- `frame` from current global phase selection

Lookup:
- `sprite = index[{plane, terrain_kind, mask_string, frame}]`

Fallback order:
1) same key with frame 0
2) same key with any available frame (pick lowest)
3) `mask_string = "00000000"` with same frame
4) `mask_string = "00000000"` frame 0
5) debug tile (solid magenta + text)

### 4) Phase Handling
Support both frame styles:
- `-frame1..frameN` (prefer if present)
- suffix letters `a..e`

Global phase picker value can be any integer; resolve to actual frame by:
- `frame_effective = phase_input % frame_count_for_key`

### 5) Client Rendering
Serve PNGs as static assets:
- place under `priv/static/momime/...` OR configure `Plug.Static` to serve `resources/`.
- JS canvas renderer loads images by URL and draws them per-tile.
- Cache `Image` objects in JS to avoid reloading.

---

## Minimal Target (Must Hit First)
Using only `ocean`, `shore`, and one land terrain (e.g., `grasslands`):
- oceans coherent
- coastlines align
- phase changes shimmer without scrambling terrain family

Then expand terrain kinds.

---

## Notes
- `river/` is an overlay set driven by river connectivity; do not treat as base terrain.
- node folders and volcano likely belong to special overlays; render later.

---

End of document.
