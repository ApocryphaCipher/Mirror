# Mirror (Part 1 of 2) — Core Save Editor + Data Terrain (Codex Prompt Pack)

This file is **Part 1**. It focuses on building Mirror’s core Phoenix/LiveView app, Classic save parsing/patching, two-plane map viewers, multi-layer editing, and the “data terrain” research system (ETS/DETS stats + ray vision).

**Important**: This document is designed to be pasted into Codex as a single prompt (or broken into sections). Do not mix with Part 2 unless you intend to implement LBX decoding and visual tile rendering.

---

## Project Overview (Part 1 Scope)

Mirror is a Phoenix LiveView application for **Master of Magic Classic** save editing. Mirror edits the save file **surgically**: decode → mutate structured state → serialize back to a valid save file. In v1, priority is the map editor and research dataset; authentic tile art rendering is optional (placeholder rendering is fine).

### Core Goals
- Open Classic save file, parse map-related blocks for both planes.
- Provide plane viewers/editors:
  - `/arcanus`
  - `/myrror`
- Provide layer stack UI:
  - Terrain (u16 per tile)
  - Terrain flags (u8 per tile)
  - Minerals/resources (u8 per tile)
  - Exploration (u8 per tile)
  - Landmass id (u8 per tile)
- Editing UX (modernized TSR-style):
  - Left click/drag paint; right click sample.
  - Mouse wheel cycles values; modifiers change domain.
  - Persist selection across planes.
  - Undo/redo (stroke-based diffs).
- Save writes:
  - backup (.bak) before first write
  - modified save output
- **Data Terrain research system**:
  - Persistent stats across saves via ETS/DETS
  - Histograms for raw u8 layers (0..255)
  - Derived/computed adjacency masks (0..255) from terrain type comparisons
  - “Ray vision” 5×5 / ray2 stats to infer coastline/transition logic over time
  - UI to label unknown u8 values/bits (“???” → named), persisted

---

## Runtime + Platform Assumptions
- Windows 11
- PowerShell 7
- Elixir + Erlang installed (via asdf, mise, or official installer)
- Phoenix installed (mix archive phx_new)

---

## App Structure

### Key Modules
- `Mirror.SaveFile`
  - `load(path) :: {:ok, %Save{}} | {:error, reason}`
  - `serialize(%Save{}) :: iodata()`
  - `write(%Save{}, path, opts)` (handles backups)
- `Mirror.SaveFile.Blocks`
  - Encapsulates offsets/sizes for map-related blocks (Classic save spec).
  - Provides generic get/put plane slices.
- `Mirror.Map`
  - Pure functions for tile indexing, get/put, bulk ops, stroke diffs.
- `Mirror.Map.Rays`
  - Computes ray features from a plane’s terrain grid (wrap/clamp rules).
  - Emits observations to stats system.
- `Mirror.Stats`
  - ETS accumulator + DETS persistence
  - Merge/flush/export/import
  - Naming system for values/bits
- `MirrorWeb.MapLive` (shared LiveView)
  - Params: `plane=:arcanus|:myrror`
  - Renders layer stack, palette strip, canvas
  - Handles input events from JS hook
- `MirrorWeb.MapHooks` (JS hook)
  - Canvas rendering (placeholder)
  - Sends normalized events: hover, click, drag, wheel, modifiers
  - Applies incremental patches from server (tile updates)

### State Model
- Save session state in ETS keyed by `session_id` (or LiveView pid + unique ref).
- Store:
  - loaded save binary
  - decoded map layers per plane
  - edit history stack (undo/redo)
  - active layer, active selection, tool mode
- Persist stats globally in DETS (not per-session).

---

## Map Geometry & Topology
- width = 60, height = 40
- planes:
  - 0 = Arcanus
  - 1 = Myrror
- horizontal wrapping (x): wrap
- vertical (y): clamp (off-map treated as no-match/none)

Provide helper:
- `idx(x,y) = y*60 + x`

---

## Layers & Byte Layout (Core Editor)

### Storage Representation
For each plane and layer store a binary:
- u16 terrain: 4800 bytes (60*40*2), little-endian
- u8 layers: 2400 bytes (60*40)

Expose generic API:
- `get_tile_u8(bin, x, y)`
- `put_tile_u8(bin, x, y, val)`
- `get_tile_u16_le(bin, x, y)`
- `put_tile_u16_le(bin, x, y, val)`

The actual offsets/sizes should live in `Mirror.SaveFile.Blocks` as constants, with a single generic “slice plane” function:
- `plane_slice_offset = base_offset + plane_index * plane_size`

---

## Editing UX (Input Contract)

### Tools
- `:paint` (default): applies current selection
- `:sample`: right click samples into selection (or Ctrl+Right for layer-specific sample)

### Modifiers
- No modifier:
  - wheel cycles *variant* within the active domain
  - left paint
- Alt:
  - wheel cycles *type/category* within the domain (bigger step)
- Ctrl:
  - toggles “copy/paint sampled” mode (fast fill)
- Shift:
  - toggles “secondary rotate” within active layer (roads/resources submodes)

### Event Payload (JS → LiveView)
Send events like:
- `map_pointer` with `{x,y, buttons, mods, wheel_delta, tool, layer}`
- `map_drag` streaming tile coords (rate-limited)
- `set_active_layer`
- `set_selection`
- `undo`, `redo`, `save`

### Server → Client Patch
- `tile_update` `{plane, layer, x, y, new_value}`
- `stroke_applied` (optional)
- `reload_plane` (fallback)

---

## Research System (Data Terrain)

### Stats Schema (Tiny, Stable)
Use DETS file `mirror_stats.dets` with tuple keys. Namespaced by dataset id:
- `dataset_id = {:mom_classic, asset_fingerprint}` (fingerprint method can be “size+mtime hash” of a few LBX files, or just a user-provided string in v1).

Keys:
- `{:meta, dataset_id}` -> %{schema_v: 1, created_at: int, updated_at: int}
- `{:name, dataset_id, layer, :value, byte}` -> string
- `{:name, dataset_id, layer, :bit, bit_index}` -> string
- `{:hist, dataset_id, layer, :global}` -> 256-bin list
- `{:hist, dataset_id, layer, {:plane, plane}}` -> 256-bin list
- `{:hist, dataset_id, layer, {:terrain_type, t}}` -> 256-bin list
- (optional) `{:co, dataset_id, layer_a, layer_b, :global, {va, vb}}` -> count (sparse)
- Ray vision:
  - `{:ray, dataset_id, center_class, dir, hit_class, dist}` -> count
  - `{:ray_pair, dataset_id, center_class, {dir1, hit1, dist1}, {dir2, hit2, dist2}}` -> count

### Derived Layers
- `:computed_adj_mask`:
  - for each tile, compute 8-neighbor match mask from base terrain *type* comparison
  - store histogram and/or per-terrain-type hist

### Ray Vision (radius=2 to start)
For each tile, cast rays in 8 directions:
- step 1 and step 2
- record first differing terrain class and distance, or :none

Use coarse classes initially:
- `:land`, `:water`
Optionally add `:mountain` or other families later.

### UI
- “Research” side panel per layer:
  - histogram values sorted by count
  - click value -> assign name (persist)
  - bit inspector with 8 toggles and optional bit names
- “Hover vision” overlay:
  - show rays and first-hit distance
  - show computed adj mask value

### Export
Add an endpoint/button to export stats to JSON (portable):
- schema_v
- dataset_id
- histograms
- names
- ray counts

---

## Deliverables (Part 1)
By end of Part 1, Mirror must:
- run as Phoenix LiveView app
- open a Classic save (user file picker or path input)
- show Arcanus/Myrror map views
- show/edit layers with click/wheel/modifiers
- save modified file + backup
- collect and persist stats across sessions (ETS/DETS)
- offer stats export to JSON

---

## Non-goals (Part 1)
- Accurate terrain sprite rendering from LBX
- Full LBX extraction tooling
- Full engine-equivalent blob reduction table reproduction
Those are Part 2.

---

## Codex Work Plan (Part 1)
Codex should:
1) Create Phoenix app + LiveView routes for `/arcanus` and `/myrror`
2) Implement SaveFile codec for map blocks (decode/encode and patch)
3) Implement Map editing core (get/put, undo/redo diffs, selection cycling)
4) Implement placeholder rendering via canvas hook
5) Implement Stats (ETS+DETS) + UI for labeling and histograms
6) Implement derived computed adjacency mask + ray vision collection

Keep modules pure where possible; isolate IO and storage.
