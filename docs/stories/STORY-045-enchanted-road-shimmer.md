# STORY-045: Enchanted roads shimmer

**Parent:** [EPIC-005](../epics/EPIC-005-animated-terrain-and-magic.md)
**Status:** implemented and checked against the real game (2026-10-07). It builds on
STORY-008's overlay clock, so it ships after (or with) that story.
**Size:** small
**Requested by:** [Kevin](https://github.com/KevinAsbury), 2026-10-07, after seeing the
node sparkles: "the road shimmer is the only thing I see missing".

## What

The game's enchanted roads change colour in a slow shimmer. Mirror drew them at their
first frame only. They now step on the shared animation clock (STORY-007/008), with
the same "Animate terrain" toggle, the same 0.6 s step, and the same pause while the
tab is hidden.

## What the game does (measured 2026-10-07)

Screenshots of three enchanted Myrror road tiles through the DOSBox fork's API,
compared with `MAPBACK #54..#62` (the enchanted pieces, 6 frames each):

- **The six frames are three pictures:** frames 0, 2, 4 are identical (colour A,
  `190,125,20`), 1 and 5 are identical (B, `166,109,28`), and 3 is brighter (C,
  `206,138,24`). So a cycle looks like A B A C A B.
- **Every tile and every piece shows the same frame at once.** The three tiles
  and their pieces (centre, NE, S, N, SW) were on one frame at every sample.
  This differs from the node sparkles, whose tile *i* is `i` frames ahead.
- **The pace is the same 0.6 s step** as the rest of the overland animation. Over 8 s
  the road went A, B, A, C, A, B, A, B, A, C, A, B, A, B at about 0.6 s a step, which
  is the cycle above running on.

So an enchanted road piece is drawn as `frame = step mod 6`. Frame 0 is the colour
drawn before this story, so turning the animation off leaves the old picture. Plain
roads, specials and corruption do not animate.

## What was built

- `map_overlays.js`: the `roads` drawer picks `phase mod 6` for an enchanted road's
  pieces and frame 0 for everything else.
- The overlay clock now also runs when the Roads & specials layer is visible and holds
  an enchanted road (`hasEnchantedRoad` in `terrain_animation.mjs`, updated each time
  the layer's items arrive), so placing the first enchanted road with the Road tool
  starts it and removing the last one stops it.
- No server change: the roads overlay already says which roads are enchanted.

## Checked

- Node tests: an enchanted piece follows the step and wraps over 6; every tile is on
  the same frame; a plain road stays on frame 0; no phase means frame 0; specials are
  untouched; `hasEnchantedRoad` is true only for an enchanted road item.
- Mirror's canvas (the Docker image, a Myrror save with 13 enchanted road tiles, the
  roads layer alone), 12 steps = two cycles: the road colour on those tiles was exactly
  A, B, A, C, A, B, A, B, A, C, A, B, and 3,521 road pixels were drawn at every step; the
  specials sharing those tiles and the 11 plain roads were identical at every step.
- The clock runs while an enchanted road is on screen, stops when the checkbox or the
  Roads & specials layer is turned off, and starts again when turned back on.

## Not yet seen

As with the sparkles, nobody has watched Mirror's roads shimmer on screen: the browser
pane was hidden, so the clock was stepped by hand. Only Myrror's enchanted roads were
measured in the game (Arcanus has none in these saves); the shimmer is the same art, so
the same frames apply.
