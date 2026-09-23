# STORY-029: Safe map editing: see everything, and don't create impossible states

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** later. **Blocked** on decoding and drawing the other layers:
EPIC-004 (cities, sites, **units**, roads, **specials**) and the
exploration (fog-of-war) layer's meaning.
**Size:** medium–large
**Raised by:** Kevin, 2026-09-23

## The problem

Heavy terrain editing on a real save, especially a brand-new game on turn
one, is only safe if you can see what the terrain supports:

- **Fog of war.** On turn one most of the map is unexplored for the
  player. You need to see *everything*, not the player's view, while
  editing. (MMS had "reveal all" for exactly this.)
- **Impossible or odd states** an edit can create:
  - land units standing on water (a tile turned to ocean under an army);
  - ships stranded on land;
  - cities, lairs, towers or nodes whose tile changes type under them;
  - roads over ocean. MMS says the game allows this as a "bridge", so it's
    a warning, not an error: "truly magic!";
  - specials or bonuses (below) left on terrain that can't hold them.

## What to do (once unblocked)

1. **"Show everything" toggle** in edit mode: ignore exploration/fog, show
   all units, sites and specials. Needs the exploration layer's bits
   understood (they're mostly `0`/`255`-ish today; not yet decoded).
2. **An edit checker** that runs after each stroke and flags problems on
   the map (outline plus tooltip). Warn, don't block; some odd states are
   legal and fun (bridges).
3. **Brush safety for STORY-028**: big brushes skip or ask about tiles
   holding units, cities, sites or specials.
4. **Structure-aware moves** are already scoped in STORY-019; this shares
   the checker.

## Order of work

EPIC-004 decode and draw (cities → units → sites → roads and specials) →
exploration layer decoded → this story → big brushes in STORY-028 and
STORY-017's type painting.
