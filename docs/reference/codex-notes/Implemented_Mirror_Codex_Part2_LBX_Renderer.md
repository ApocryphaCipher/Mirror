# Mirror (Part 2 of 2) — LBX Decode + Tile Probe + Visual Renderer (Codex Prompt Pack)

This file is **Part 2**. It focuses on decoding LBX containers, extracting/decoding images, building a “Tile Probe” UI to label tiles, and upgrading the map renderer from placeholders to authentic Master of Magic Classic visuals.

Do not start Part 2 until Part 1 is working end-to-end (open/edit/save + research stats).

---

## Part 2 Scope

### Goals
- Implement LBX container reader and image decoder (at least for the files needed for overland tiles).
- Add asset cache for decoded images.
- Add “Tile Probe” UI:
  - browse LBX files
  - paginate through entries
  - preview decoded frames
  - label entries (persist mapping JSON)
- Add mapping system:
  - map “terrain type + adjacency class + overlays” -> {lbx_file, entry_index}
- Upgrade canvas renderer to draw authentic tiles (base + overlays).

---

## LBX Handling

### References
Use the documented LBX container structure (header + entry offset table). Implement based on spec and cross-check with existing tools (lbxtract-go / lbx-tool).

### Module API
- `Mirror.LBX.open(path) -> {:ok, lbx}`
- `Mirror.LBX.entries(lbx) -> [%{index: int, type: atom, offset: int, size: int}]`
- `Mirror.LBX.read_entry(lbx, index) -> {:ok, binary}`
- `Mirror.LBX.decode_image(lbx, index) -> {:ok, %Image{w,h,rgba}}` (supports palette-indexed frames)

### Caching
- `MIRROR_TILE_CACHE` directory stores decoded RGBA PNGs (or raw RGBA + metadata).
- Cache key includes:
  - lbx filename
  - entry index
  - decoder version

---

## Mapping Data (User-Labeled)

### Mapping Store
Persist a JSON file under `MIRROR_ASSET_MAP`:
- `terrain_tiles.json`
- `overlay_tiles.json`

### Schema (start simple)
- `{"lbx":"COMPix.LBX","index":123}` references
- allow groups:
  - `"grass": [{"lbx":"...","index":12}, {"lbx":"...","index":13}]`

### Labeling UI (“Tile Probe”)
- Browse LBX file list from `MIRROR_MOM_PATH`
- Select LBX → show grid of entries
- Click entry → show large preview + metadata
- Add tags:
  - terrain type group: grass/ocean/shore/...
  - overlay group: road/corruption/resource
  - variant hints: “shore_E”, “corner_NE”, etc.
- Save mapping JSON

---

## Renderer Upgrade (Authentic Tiles)

### Rendering Pipeline
1) Determine base terrain type per tile (from terrain u16)
2) Compute adjacency signature:
   - computed 8-neighbor mask for same-type match
   - optional ray features (for better heuristics)
3) Use mapping + (optional) blob-reduction lookup to choose base tile image
4) Apply overlays from flags layer:
   - road connections: compute adjacency within road bit and select overlay sprite
   - river connections similarly (often 4-dir)
   - corruption as tint or alt overlay
5) Apply specials/resources:
   - draw 1:1 icon or adjacency-aware aura if modeled

### Blob Reduction Table
If available/derivable, implement a reduction from 256 masks to fewer sprite classes.
If not, use mapping groups by tagged variants and fallback rules.

### Client Rendering
Continue rendering on canvas in JS hook:
- Preload decoded tile atlas images
- Draw base tile
- Draw overlays in order
- Support zoom/pan efficiently

---

## Deliverables (Part 2)
- LBX reader + decoder
- Tile Probe UI + mapping persistence
- Authentic map rendering (at least base terrain + 1 overlay category)
- Cache and fast startup behavior

---

## Non-goals (Part 2)
- Perfect 1:1 reproduction of every engine edge case at launch
- EXE disassembly integration
- Full procedural generation (unless explicitly requested later)

---

## Codex Work Plan (Part 2)
1) Implement LBX open/entries/read/decoder
2) Implement cache
3) Build Tile Probe LiveView
4) Define mapping JSON schema + persistence
5) Upgrade renderer to use decoded tiles
6) Add overlay rendering incrementally
