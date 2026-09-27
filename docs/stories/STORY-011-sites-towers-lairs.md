# STORY-011: Towers, fortresses, lairs, ruins and other sites

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** done. Towers of Wizardry and intact encounter-zone sites
(mounds, temples, keeps, ruins) decode from `Mirror.SaveFile.Sites` and
draw as their own `"sites"` overlay layer (`map_live.ex`'s `site_items/2`,
`map_overlays.js`'s `sites` drawer). Node guardians (kinds 1–3) draw
nothing — the node itself is a terrain tile. Tower encounter records
(kind 0) draw nothing either — the tower icon comes from the `towers`
block, on both planes unconditionally, since a tower has no plane byte
(checked: it stands on both).

Explicitly **not** drawn, deferred: the "Wizard fortresses" block
(`0x0065f8`) — it's each wizard's capital *city*, already fully visible
via the existing city overlay (STORY-010/032), and there's no separate
fortress sprite in the catalog — and cleared sites (`intact: false`),
which are filtered out entirely rather than guessed at. Layouts for
fortresses (checked), towers (no plane byte) and encounter zones (kind
table and sprite per kind) are in
[kazzmir-save-layouts.md](../reference/kazzmir-save-layouts.md). Checked
on SAVE1: each node kind's realm matches its node (all 30). Tower
defenders are encounter records on both planes (0–5 Arcanus, 6–11
Myrror).
**Live RAM (2026-09-24):** guard nibbles settled (low = left, high =
starting); several kinds checked on screen; still open: the `+15`
explored-by flags and the cleared look. See
[the evaluation](../notes/2026-09-24-live-ram-evaluation.md).
**Size:** medium

## What was done

1. **Decoded** (already existing in `Mirror.SaveFile.Sites`, unchanged by
   this story): Towers of Wizardry (`0x006610`) and encounter zones
   (`0x006628`), each with x/y/(plane)/owner or intact/kind.
2. **Drawn**: the `MAPBACK.LBX` `SITES` icons for towers (unowned #69 /
   owned #70) and intact encounter kinds 4–10 (mound #71, ancient temple
   #72, abandoned keep #73, ruins #74, fallen temple #75).
3. Towers draw on both planes at the same x/y, unconditionally (not
   gated on the viewed plane), matching the note above.

## Definition of done

- Every tower and intact encounter zone in a loaded save is drawn with
  the right icon on the right tile. **Not covered** (see above,
  intentionally out of scope): the Wizard fortresses block and cleared
  sites.
