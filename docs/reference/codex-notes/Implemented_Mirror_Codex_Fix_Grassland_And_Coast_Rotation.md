# Mirror Codex — Fix “All Land Is Grass” + Wrongly Rotated Coasts (MOMIME PNG Renderer)

## Goal
Fix two issues in the MOMIME PNG terrain renderer backend:

1) All land tiles render as grasslands (terrain_kind collapse)
2) Coast/shore tiles render with correct shapes but wrong rotation (adjacency bit-order mismatch)

This is not a palette or canvas geometry issue.

---

## Part A — “All Land Is Grass” (TerrainKind Normalization Fix)

### A1) Verify Terrain(u16) Read Is Little-Endian
Confirm the terrain grid is decoded as u16 little-endian:
- `val = lo + (hi <<< 8)`
- `lo = byte0`, `hi = byte1`

Add temporary logging for a small sample:
- pick 50 random land tiles (non-ocean)
- log: `val`, `lo`, `hi`, and current `terrain_kind(val)`

If `lo` looks constant or nonsensical for known terrain, endianness/extraction is wrong.

### A2) Stop Using “land vs water” Only
Current behavior likely classifies:
- ocean -> `:ocean`
- otherwise -> `:grasslands`

Replace with a stable mapping:
- derive `base_id = terrain_u16 &&& 0x00FF` (or the known base-id mask)
- map base_id -> TerrainKind

### A3) Implement a Provisional TerrainKind Map (Minimum Set)
Create a small lookup table for base_id -> kind folder.
Start with these folders (must exist in resources):
- `ocean`
- `shore`
- `grasslands`
- `desert`
- `forest`
- `hills`
- `mountains`
- `swamp`
- `tundra`

Unknown base_ids must render as a debug tile (magenta + text), NOT grass.

### A4) Add a Debug Overlay (Temporary)
Add a toggle to display the resolved TerrainKind per tile (text or colored tint).
This validates mapping without needing perfect art.

---

## Part B — Coast Rotation Wrong (Adjacency Bit Order Fix)

### B1) Diagnose Bit Order vs MOMIME Mask Convention
MOMIME file names encode adjacency masks as an 8-bit binary string:
- `00111111.png` etc
Your computed `adj_mask` must match MOMIME’s direction→bit mapping.

Pick a simple coastline tile and log:
- its 8 neighbors (water vs land)
- the computed adj_mask (0..255)
- the binary string used for lookup

If the coastline appears rotated 90°/180°, the bit order is rotated.

### B2) Implement Mask Rotation Utilities
Add functions to rotate an 8-neighbor mask in 90° steps:
- `rotate90(mask)`
- `rotate180(mask)`
- `rotate270(mask)`

(These rotate the directional bits, not the integer bits blindly.)

### B3) Add a Runtime Diagnostic Fallback (Fast Fix)
During sprite lookup for `shore` (and optionally `ocean`):
Try masks in this order until a file exists:
1) `mask`
2) `rotate90(mask)`
3) `rotate180(mask)`
4) `rotate270(mask)`

Record which rotation was used most often.
Once stable, set that as the canonical mapping and remove fallback.

### B4) Canonical Direction→Bit Mapping (Final Fix)
After observing rotations, align the computed mask ordering to MOMIME’s.
Then remove lookup-time rotation and use the canonical mask directly.

---

## Validation Checklist

### Land Kinds
- Desert regions render as desert tiles
- Forest renders forest
- Mountains/hills are not grass
- Unknown base IDs show debug tile, not grass

### Coasts
- Shore edges align to land/water boundary
- Corners appear in correct orientation
- Rotation fallback (if enabled) converges on one consistent rotation

---

End of document.
