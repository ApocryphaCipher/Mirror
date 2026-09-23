# STORY-027: Cycle tool: clicking a tile steps to the next tile picture

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** done 2026-09-23. `🔄 Cycle` (default) and `🎨 Paint` in the edit
toolbar. Cycle: click +1, right-click or shift-click −1, wrapping 0–761, one
undo step per click, redrawn live. The readout shows `tile 134 → 135` and
follows the clicked tile. Paint is the old click-to-stamp behaviour, with
the brush shown only for Paint.
**Not yet:** remembering the tool per browser; the land↔water warning
(needs the tile-number→terrain-type mapping first, STORY-017/029); a
separate Pick tool (right-click in Paint already picks).
**Size:** small–medium
**Requested by:** Kevin, 2026-09-23

## Intent (Kevin)

> How I intended tiles to work was: I click the tile and it cycles the
> tile art to the next # in the tiles. If a tile is on terrain picture
> #134, clicking advances it to 135… click again and it's 136.

And about today's behaviour, where a click paints the brush's tile number:
"it is effectively a tile-painting mode!!! This can be turned into a tool
of its own. I don't want edit mode to necessarily work this way right off
the bat, but I love the idea."

## What to do

Turn Terrain editing into **named tools**, with **Cycle** as the default:

| Tool | Left click | Right click | Drag |
| --- | --- | --- | --- |
| **Cycle** (default) | tile number **+1** | tile number **−1** | none (clicks only) |
| **Paint** (today's behaviour, renamed) | stamp the brush tile | pick the tile under the cursor into the brush | paints a stroke |
| **Pick** (optional; right-click already does this) | copy the tile into the brush and switch to Paint | | |

- Cycle wraps within valid tile numbers **0–761** (761 → 0, 0 → 761).
- Each Cycle click is **one undo step**. Rapid clicking should still be
  cheap: one tile per event, pushed live (STORY-023 fixed live pushes).
- Show the tool as a segmented control in the edit toolbar, e.g.
  `Cycle | Paint | Pick`. Remember the choice per browser.
- Show the brush picker (tile number + preview) only when Paint is
  selected.
- The hover readout (and STORY-024's highlight, once built) should show
  what the tile will become: "tile 134 → 135".
- Optional shortcut: Shift+click on a tile for −1, for trackpad users
  without an easy right click.

## Later: smarter cycling (STORY-017)

MMS's editor distinguishes cycling the **picture within the same terrain
type** (L/R) from cycling the **type** (Alt+L/R). Once STORY-017 maps tile
numbers to terrain types, Cycle can gain a "same type only" mode: step to
the next shore variant instead of jumping from shore into grassland. Plain
±1 is the right first version: simple, predictable, and exactly what Kevin
described.

## Continents (landmass layer)

A Cycle step can turn land into water or back (e.g. stepping from a
shore picture into grassland). Until the landmass rule is decoded
(STORY-029), **flag** such steps rather than silently leaving the tile's
continent ID stale: show a warning in the readout, and record the change
for the edit checker.

## Definition of done

- In edit mode with **Cycle** selected, clicking a tile on #134 shows #135
  immediately; clicking again shows #136; right-click steps back.
- **Paint** keeps today's behaviour exactly.
- Undo steps back one click at a time.
- LiveView tests: cycle +1, −1, wrap at both ends, and undo.
