# STORY-046: Tower of Wizardry: what clearing it changes, and its lit look

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** open, ready to start. Nothing is decoded about this yet beyond the guesses below.
**Size:** small to medium (mostly one live experiment)
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-07: the game draws a Tower of
Wizardry differently, "lit up", once it has been cleared of its occupants.

## What we know, and what we only assume

- Mirror already draws two tower pictures, and picks between them on the tower block's
  **owner byte** (`map_live.ex`'s `site_items/2`): `MAPBACK.LBX #69` when it is unowned, `#70`
  when it has an owner ([sprite catalog](../reference/overland-sprites-and-save-blocks.md)). Both are
  one frame, 20 x 18, drawn on both planes (a tower has no plane byte). **Checked:** nothing about
  the choice. In SAVE1 every tower is unowned, the names "unowned" and "owned" come from the name
  table, and the pictures were never compared with the game on a cleared tower.
- The tower record is `x, y, owner, ?` at `0x6610`, 6 x 4 bytes. The fourth byte is unexplained
  (0, 78 and 39 in SAVE1) and could matter here.
- A tower's guards are **two encounter records** (an Arcanus side and a Myrror side, same x/y, same guards),
  matched to the tower by position only; there is no link field. The docs list "clear one side, then diff
  the two records" as a to-do that was never done
  ([kazzmir-save-layouts.md](../reference/kazzmir-save-layouts.md)).
- *Guess:* the lit look is `#70` and the owner byte is what changes when a wizard clears the tower. Neither is
  known. It could as well be driven by the encounter records' `intact` byte, or by the unexplained fourth byte.
- *Unknown:* whether the lit tower animates (every other animated thing in the overland map steps every
  0.6 s), and whether both planes show it.

## Questions to answer

1. **What does the game write when a tower is cleared?** The tower's owner byte, its fourth byte, both
   encounter records or only the side entered, and the guard count nibbles (low = left, per STORY-011).
2. **What does it draw** for an uncleared tower, a cleared one, and one cleared by another wizard (does
   the picture or its colour follow the owner)? On each plane. Animated or still?
3. **Is it `#70`?** Compare the game's pixels with the decoded `#69` and `#70` frame by frame.

## How (two steps, the first is cheap)

1. **What the game draws for given bytes.** Build a save from SAVE3 with Mirror's code (as for the nodes in
   STORY-008): set one tower's owner to Freya (wizard 0), clear its two encounter records (`intact` 0, guard
   count low nibbles 0), leave another tower untouched. Load it in the fork, screenshot both towers on both
   planes, and compare the crops with `#69` and `#70` as in
   [real-game-acceptance.md](../reference/real-game-acceptance.md). This shows the look, not what the game
   itself writes.
2. **What the game writes.** Clear a tower in play with the fork's checkpoints (or its memory signatures)
   around the fight, and diff the tower block and both encounter records before and after. In RAM the tower
   block is at `0x086610` and the encounter records at `0x086660`, but **the node block has a stale second copy
   in RAM** ([live-ram-map.md](../reference/live-ram-map.md)), so check which copy follows the game.

## What to do in Mirror

- Draw the lit tower the way the game does, from whichever bytes turn out to drive it (the owner byte, or the
  cleared state of the encounter records), on both planes. If it animates, use the shared overlay clock
  (`phaseAt`, the "Animate terrain" toggle).
- Update `site_items/2` and the sprite catalog, and add a test on a synthetic save that has a cleared tower.
- STORY-011 also left **the cleared look of lairs and other sites** open (they are filtered out when
  `intact` is false). The same experiment may answer it; if so, do it here or write it up for its own story.

## Done when

- A save with a cleared tower draws it as the game does, on both planes, matched against a real screenshot
  (all pixels of the sprite, not "looks right").
- The bytes the game changes on a clear are written into `kazzmir-save-layouts.md`, marked checked.
- A test covers the decision between the two looks.
