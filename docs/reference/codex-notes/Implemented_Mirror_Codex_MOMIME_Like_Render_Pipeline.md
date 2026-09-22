# Mirror Codex — Make Draw Phase MOMIME-Like (Coherent Terrain Rendering)

## Goal
Replace the current “confetti/noise” tile draw behavior with a MOMIME-like rendering pipeline:
- Normalize terrain into a small set of **TerrainKind** values
- Compute adjacency on **TerrainKind** (not raw u16)
- Reduce adjacency masks (“blob reduction”) into a small sprite class set
- Select sprites only from the correct **tileset groups** per TerrainKind
- Apply overlays in separate passes

This is about **behavioral correctness**, not cosmetic tweaks.

---

## Root Cause (Why It Looks Like Garbage)
The renderer is effectively selecting images from the wrong space:
- using raw u16 values as sprite keys, or
- choosing LBX entries via modulo/range without semantic grouping, or
- drawing overlay/FX tiles as base terrain tiles.

MOMIME looks coherent because it enforces strict invariants before drawing.

---

## Required Rendering Invariants (Must Implement)

### 1) Terrain Normalization
Convert raw terrain (u16) → TerrainKind (finite):
- `:ocean`
- `:shore`
- `:grass`
- `:desert`
- `:tundra`
- `:swamp`
- `:hill`
- `:mountain`
- `:unknown` (fallback; never treated as base tile)

Important:
- TerrainKind mapping must be stable and not “one kind per u16.”
- Start with a minimal mapping that makes oceans/continents readable.
- Unknown values must render as a debug tile, not random art.

### 2) Adjacency on TerrainKind
Compute `adj_mask` using TerrainKind equality rules:
- For coast: treat `:ocean` vs “non-ocean” boundary as the primary edge.
- For land families: optionally compute adjacency within the same land kind.

Do NOT compute adjacency on raw u16 IDs.

### 3) Blob Reduction
Do not assume a unique sprite exists per 0..255 mask.
Reduce `adj_mask` to a smaller `edge_class`:
- interior
- edge (N/E/S/W)
- corner (NE/NW/SE/SW)
- thin peninsula / bay variants (optional)
- fallback

Start simple:
- Implement blob reduction for ocean/shore first (highest visual impact).
- Add more classes incrementally.

### 4) Tileset Grouping
Define tileset groups per TerrainKind:
- Each group is a small list of LBX {file, entry_index} candidates,
  split by edge_class and by phase.
- The renderer must NEVER select tiles outside the active group.

This is the primary “stop the confetti” rule.

### 5) Phase (Animation Frame)
Respect phase variants as time slices:
- `phase_effective = phase % variant_count` per group
- Draw exactly one variant per tile per frame (no stacking phases)

### 6) Overlay Passes (Separate Draw Calls)
After base terrain draw, apply overlays in order:
1) terrain features (forest canopy, dunes, rocky noise, etc.)
2) flags overlays (roads, rivers, corruption)
3) specials/resources overlays

Overlays are driven by separate layers/flags, not by base TerrainKind.

---

## Concrete Pipeline (Function Signatures)

### Normalization
```elixir
@spec terrain_kind(terrain_u16 :: non_neg_integer) :: atom()
def terrain_kind(terrain_u16), do: ...
```

### Adjacency + Reduction
```elixir
@spec adj_mask(kind_grid, x :: integer, y :: integer) :: 0..255
def adj_mask(kind_grid, x, y), do: ...

@spec edge_class(kind :: atom(), adj_mask :: 0..255) :: atom()
def edge_class(kind, adj_mask), do: ...
```

### Sprite Lookup
```elixir
@spec sprite_ref(kind :: atom(), edge_class :: atom(), phase :: non_neg_integer) ::
        {lbx_file :: binary(), entry_index :: non_neg_integer} | :missing
def sprite_ref(kind, edge_class, phase), do: ...
```

### Draw
```javascript
// JS hook / canvas draw loop must:
drawBaseTile(x,y, sprite_ref)
drawOverlays(x,y, overlay_refs...)
```

---

## Minimum Coherent Milestone (Must Hit First)
Implement a coherent renderer for **only**:
- ocean interior
- coast/shore boundary
- generic land interior (single land kind)

If this milestone is met, the world becomes readable.
Then extend terrain kinds and overlays incrementally.

---

## Validation Checklist
- Oceans render as a coherent field (not confetti)
- Coastlines form continuous edges/corners
- Landmasses are contiguous and visually stable
- Phase changes affect shimmer but do not scramble terrain families
- No overlay tiles appear as base tiles

---

End of document.
