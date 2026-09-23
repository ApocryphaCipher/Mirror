# STORY-028: Floating tool palette, Cycle instructions and Paint panel

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open, nice-to-have. **After STORY-027** (the tools must exist)
and after STORY-029's prerequisites for anything beyond single tiles.
**Size:** medium
**Requested by:** Kevin, 2026-09-23

## The idea

In edit mode, the tools float over the map as a **column of buttons in the
upper-left corner**, one per tool, each with its own emoji:

- 🔄 **Cycle**
- 🎨 **Paint**
- (room for more later: 🛣 Roads, 🏰 Structures, 🧙 Units, 💎 Specials…)

The selected tool is highlighted, with a tooltip naming it and its
shortcut. The column replaces the tool choice in the toolbar; the toolbar
keeps Undo, Redo, the counter, Discard and Save as.

## Per-tool context

**🔄 Cycle**: an instructions strip above the map:
"Click: next tile (134 → 135) · Right-click / Shift+click: previous ·
Space+drag: pan · Esc: done".

**🎨 Paint**: a small panel:

- **Brush size**: 1×1, 3×3, 5×5 (maybe a round brush too).
- **Quick terrain buttons**, each setting the brush to a **default tile**
  for that terrain: Grassland · Desert · Forest · Mountain · Hill ·
  Ocean · Tundra (and later Swamp, and the Chaos / Nature / Sorcery node
  tiles).
- The existing tile number box and preview, for any specific tile.

## Prerequisites and open questions

- **Default tiles need labels.** Someone has to pick, per terrain, the tile
  number that counts as "plain X" (e.g. plain grassland = `0xA2` per the
  early tile-range read). That's a small table, best derived with
  STORY-017's tile number → terrain type mapping. Store it in one place
  (e.g. `Mirror.TerrainTiles`) with the source noted.
- **Brushes bigger than 1×1 need auto-tiling to look right.** Stamping a
  3×3 block of one grassland tile into an ocean gives hard square edges,
  with no shore transitions. Until STORY-017 (paint types; the game's
  `TERRTYPE.LBX` table picks the pictures) lands, either ship size 1 only
  or clearly label bigger brushes as "raw stamp".
- **Safety:** big brushes make it easy to break game state (land under
  ships, sea under armies). See STORY-029. Ship the palette with single
  tiles first; gate the big brushes on STORY-029.

## Definition of done (first slice)

- In edit mode, the emoji tool column shows at the upper left of the map
  and switches tools. The Cycle strip and the Paint panel appear for their
  tool.
- Quick terrain buttons set the brush to documented default tiles.
- The column doesn't block panning, zooming or the hover readout, and it
  collapses on narrow screens.
