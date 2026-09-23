# EPIC-006: Map-first UI, with an edit mode

**Status:** scoped, not started
**Owner:** [Kevin](https://github.com/KevinAsbury)
**Requested:** 2026-09-22. Kevin: "too many gadgets, gizmos, and levers
assaulting my eyes." Now that the map renders correctly, `/arcanus` and
`/myrror` should mainly *show the map*, with editing available on demand
and able to produce a new save.

## Where it stands (inventory, 2026-09-22)

`map_live.ex` puts about 28 controls on screen at once, across five panels:

| Panel | What's in it | Belongs in |
| --- | --- | --- |
| Plane view header | Undo, Redo, Render: Tiles, Snapshot, Kinds, Coast Audit, Shore Semantics, Phase index, Detect Loop, Reload Tiles, Export Snapshot, Export Stats | Undo/Redo → **Edit**. Kinds / Coast Audit / Shore Semantics → **delete** with the MOMIME path (they debug the old smoothing). Render mode, Snapshot, Phase, Detect Loop, Reload Tiles, Exports → **Lab** |
| Load/Save bar | Load path, Load save, Save path, Save | Load → **View** (tidied). Save → **Edit** ("Save as…") |
| Map editor | Layer stack (visibility, opacity, active layer), selection value, controls help | Visibility → **View** (becomes STORY-009's overlay toggles). Active layer / selection / paint → **Edit** (reworked, STORY-016) |
| Research: Value intel | Label a value, histogram | **Lab** |
| Tile inspector: Bit flag lab | Per-bit toggles, snapshot/restore/invert, bit naming | **Lab** |

"Lab" means the format-archaeology tools. They're still useful (they're
how we'll decode nodes, units and terrain flags), but they belong on their
own page, next to `/tile-probe`, not on the map.

## Target shape

- **View (default)**: the map fills the window, with pan and zoom. Minimal
  chrome: plane switch, overlay layer toggles (STORY-009), load save, an
  **Edit** button, and a hover readout (x/y, terrain, and whatever city,
  site or unit is on the tile).
- **Edit mode**: an explicit toggle. You pick **what** you're editing
  (Terrain / Roads & specials / Structures / Units), which gives you that
  layer's tools only. Nothing else can be touched by accident. Undo/redo, a
  dirty indicator, and **Save as…** (never silently overwrite the original).
- **Lab**: everything research-oriented, on its own route.

## Prior art: MoM Multiplayer Shell's editor

Kevin shared the MMS editor docs. Its model maps well onto this, with one
big difference: MMS drives everything through key chords (Alt-F2/F3/F4/F5
plus mouse button and modifier combos). **We'll use explicit mode/layer/tool
selection instead**, with left click to apply, right click to pick or
sample, and modifiers only as optional shortcuts. The ideas worth keeping:

- **Terrain**: change a tile's *picture* without changing its type; change
  its *type*; pick a type and paint it over an area.
- **Shorelines are the pain point**: there are hundreds of shore pictures.
  MMS's answer is copy-a-tile-from-anywhere (even the other plane) and
  paste. Ours can be better: paint *types* and let the game's own tile
  table choose the picture (STORY-017).
- **Roads and corruption cycle on a tile; resources cycle separately.**
  Roads on ocean tiles are legal and act as bridges.
- **Select-and-move structures**: cities (with their units), lairs, towers,
  nodes and unit stacks, anywhere including across planes. Moving a city
  carries its fortress and summoning circle. Cities on ocean are legal.
- **Per-structure edit screens** (city, lair, unit properties).

## Stories

Suggested order: STORY-014 → STORY-015 → STORY-016 → STORY-021 →
STORY-017 → then the rest as their EPIC-004 data stories land.

- [STORY-014](../stories/STORY-014-ui-triage-and-lab-route.md): triage the UI; move research tools to a Lab route; delete MOMIME-only debug toggles
- [STORY-015](../stories/STORY-015-view-mode-layout.md): view mode layout (full-window map, pan/zoom, hover readout)
- [STORY-016](../stories/STORY-016-edit-mode-shell.md): edit mode shell (toggle, pick-a-layer, tools, undo/redo, Save as)
- [STORY-017](../stories/STORY-017-terrain-editing-autotile.md): terrain editing with auto-tiling (paint types; game picks the picture)
- [STORY-018](../stories/STORY-018-roads-specials-editing.md): roads, corruption and resource editing
- [STORY-019](../stories/STORY-019-move-structures.md): select and move structures and unit stacks
- [STORY-020](../stories/STORY-020-structure-editors.md): structure detail editors (city / lair / unit)
- [STORY-021](../stories/STORY-021-save-round-trip-safety.md): save round-trip safety (byte-exact, and loads in the real game)
- [STORY-022](../stories/STORY-022-bug-raw-value-paint-artifacts.md): **bug**: stray raw-value paint (wheel silently changes the brush; bare click paints) shows up as map artifacts
- [STORY-023](../stories/STORY-023-bug-edit-paint-no-live-redraw.md): **bug**: painting in edit mode doesn't redraw the tile until reload
- [STORY-024](../stories/STORY-024-tile-hover-highlight.md): highlight the tile under the cursor (nice-to-have)
- [STORY-025](../stories/STORY-025-in-game-cursor.md): use the game's own mouse cursor over the map (nice-to-have)
- [STORY-026](../stories/STORY-026-bug-discard-and-stuck-edit-state.md): **bug**: Discard does nothing; edits feel impossible to clear
- [STORY-027](../stories/STORY-027-cycle-tile-tool.md): Cycle tool (click = next tile picture); Paint becomes its own tool
- [STORY-028](../stories/STORY-028-floating-tool-palette.md): floating emoji tool palette with Cycle instructions and a Paint panel (nice-to-have)
- [STORY-029](../stories/STORY-029-safe-editing-see-everything.md): safe editing: see everything, flag impossible states (later; blocked on EPIC-004)

Dependencies: 018–020 need the matching EPIC-004 decode stories
(013 roads/minerals, 010 cities, 011 sites, 012 units) first. 017 needs
`TERRTYPE.LBX` decoded properly.
