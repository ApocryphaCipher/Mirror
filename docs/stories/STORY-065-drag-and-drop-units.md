# STORY-065: Drag and drop units (and the other movable things)

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md) (map editing)
**Status:** open (2026-10-15), a future enhancement
**Size:** medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-15

## The idea

Today moving things is two clicks: the **Units** tool lists a tile's units, you tick the ones to move and click a tile; the **Move** tool picks up a city, tower, lair or node and you click where it goes (`move_units_click` and `MoveTool` in `map_live.ex`, `Structures.move_units/3`).
Kevin: "a great start", but the end goal is a **draggable stack**: press on a stack, drag it across the map, drop it where it should go.

## What to build

- In edit mode with the Units or Move tool, pressing on a stack (or a city, tower, lair, node) and dragging carries it: a ghost of the sprite follows the pointer and the **target tile is highlighted** (green where the drop is fine, amber where the move works with a warning, such as a land unit on water; red where it is refused). Dropping moves it.
- **Escape**, or dropping outside the map, cancels. A drop on the same tile does nothing.
- **Which units move:** the whole stack by default. *Suggestion:* the ones ticked in the Units panel move if any are ticked; otherwise the stack.
- The server side does not change: the drop sends the target tile and the same `Structures.move_units/3` and `MoveTool.move/6` run, with the same warnings, as one undo step. The click-click tool stays for anyone who prefers it.

## The catch

In edit mode left-drag is the brush and panning is Space + drag or middle-drag (STORY-026, `map_viewport.js`). A drag that starts **on a movable thing with the Units or Move tool active** moves it; a drag that starts anywhere else keeps its
current meaning (brush or pan). The picking has to use the same tile-from-pointer code as the click inspector (`tileAtViewportPoint`, `assets/js/view_click.mjs`), and the ghost and highlight are an overlay, so the map never shifts (AGENTS.md section 8).

## Definition of done

- Pure helpers (is this press on a movable thing, which tile is the pointer over, valid or not) in `assets/js/*.mjs` with Node tests.
- A LiveView test that a drop event moves the stack and reports the warnings the click tool reports.
- Checked in Chrome: dragging at several zoom levels, across the wrap-around edge, cancel with Escape, and that panning and painting still work.
