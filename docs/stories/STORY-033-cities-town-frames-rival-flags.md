# STORY-033: Cities: Town+ frames, rival flag colours, `CITYNOWA`

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** main question resolved, 2026-09-27 (live DOSBox session,
`~/.mirror/dev/DOSbox/story-033-2026-09-27/`, checkpoints 44-48 in the
Evi vault). The frame isn't `size − 1` at all: **the overland sprite (and
the game's own "Pop Size" stat) is computed live from population,
independent of the save's stored `+19` size byte**, which can go stale
(directly demonstrated: a city with size byte forced to 0 but population
24,000 rendered fully developed; one forced to size 4 with population
1,000 rendered as the smallest sprite, and its own City Screen agreed,
showing "Pop Size: 1"). Thresholds, checked with a 25-city population
grid (1,000 to 25,000 in 1,000 steps): frame 0 up to 4,000, frame 1 at
5,000-8,000, frame 2 at 9,000-12,000, frame 3 at 13,000-16,000, frame 4
(the sprite's last frame) for everything 17,000 and up — i.e.
`frame = min(4, div(population - 1, 4000))`. Cross-checked against real
(non-edited) data: Bromburg at population 4,000 showed "Hamlet" (frame
0), matching the table.
**Remaining two questions (rival flag colours beyond yellow, and
`CITYNOWA`) moved to the very-low-priority end of
[backlog.md](../backlog.md), 2026-09-27** — not worth more DOSBox time
right now (Kevin). A same-day spot-check found red/blue's flag pixels
don't cleanly match the single-ramp rule STORY-032 confirmed for yellow;
see the backlog entry.
**Size:** small (mostly playing the game and taking screenshots)

## What was found

1. **Frame comes from population, not the size byte** (see above). This
   is the fix `map_overlays.js`'s `cities` drawer and
   `map_live.ex`'s `city_items/2` need: stop reading `city.size`, compute
   the frame from `city.population` (already decoded by
   `Mirror.SaveFile.Cities`) with the formula above.
2. Rival flag colours and `CITYNOWA`: not resolved this session, see the
   backlog entry linked above.

## Definition of done

- Mirror draws the city frame from population using the table above, not
  the stale `+19` byte.
- The sprite catalog (`docs/reference/overland-sprites-and-save-blocks.md`)
  records the finding and formula.
