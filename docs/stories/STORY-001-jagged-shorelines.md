# STORY-001: Shorelines still look jagged/toothy after the rotation fix

**Parent:** [../epics/EPIC-001-terrain-rendering.md](../epics/EPIC-001-terrain-rendering.md)
**Status:** open — not yet investigated
**Reported by:** Kevin, 2026-09-22, right after PR #3 landed

## What we know

PR #3 fixed the shore/coast bitmask computation to match MOMIME's real
algorithm (same-type-as-center, no invented ternary corner-support rule).
That fix is confirmed correct at the individual-tile level: shore masks now
resolve via exact match (not fallback) against the real MOMIME PNG resource
set, and a sampled tile (`shore/01110110.png`) showed coherent, well-composed
pixel art (a water channel with proper beach-transition pixels on both
banks) when inspected directly.

Despite that, the rendered map still looks jagged/toothy along coastlines
when viewed as a whole.

**I called this "authentic 1994 chunky art style" in the PR — that was a
premature conclusion from inspecting one tile in isolation, not from
comparing against real game reference screenshots. Kevin pushed back on
that; treat it as unverified, not settled.**

## Open questions to investigate

- Compare Mirror's rendered coastline against actual classic Master of
  Magic screenshots/video (not just individual tile art) — is this really
  how the original game's coastlines looked, or is there a real remaining
  defect?
- If it's a real defect, candidates to check:
  - Canvas rendering scale/zoom — are tiles being drawn at the wrong pixel
    size relative to how MOMIME intended them to be viewed together?
  - The rotation/canonicalization fallback chain in `resolveMomimePathForKind`
    (`resolveMomimePathForShore`) — confirm exact-match tiles are being used
    for the *majority* of shore tiles on a real map, not just the one
    sampled tile. A quick instrumentation pass (log `fallbackStep` counts
    across a full map render) would settle this fast.
  - Whether Mirror is missing river-mouth handling (ternary `2` values) —
    PR #3 explicitly doesn't implement river-driven ternary yet
    (`shore_mask_digits/3` is binary-only for now), which could be a source
    of visually-wrong edges near river mouths specifically.

## Suggested next step

Before writing any more mask logic: get a real classic-MoM screenshot of a
comparable coastline and put it side by side with Mirror's render. Settles
whether this is cosmetic/expected or an actual bug in ~5 minutes, and avoids
repeating the original mistake (theorizing from a pattern instead of
checking against the real thing).
