# STORY-064: River editing

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md) (map editing); related to [STORY-063](STORY-063-spike-fantasy-terrain.md)
**Status:** open (2026-10-15), an idea to shape before building
**Size:** medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-15

## The problem

Mirror cannot edit rivers. Paint type skips them: rivers, lakes, nodes, volcanoes and the polar rows are "protected" (`@protected` in `lib/mirror/terrain_paint.ex`, [classic-terrain-format.md](../reference/classic-terrain-format.md)), and a brush
that touches one is reported as skipped or stale far more often (52% of paints against 5.5%). So a river can be neither added, moved nor removed.

## What the save stores (the key fact)

**There is no river layer in the save.** A river is just a tile number, one of **43 river tiles**. Grouping them by which sides expect water (the table in `priv/kazzmir_terrain_table.json`, counted 2026-10-15) gives **exactly the 15 non-empty combinations of
north, east, south and west**: one tile each for a river running off one side only (a spring or a mouth), 3 or 4 variants for most corners, straights and T-junctions, and 5 for the four-way crossing. So a river is a **4-connected path** (no diagonals) and
each river square's tile is decided by which of its four neighbours are water. A side that meets ocean, shore or lake counts as water, so a river mouth is just a river square with one side open to the sea. *Guess:* the several variants of one combination are different artwork (or different
neighbour kinds, river versus sea); not checked, and it decides how the tile is picked among them.

## Two ways to build it (both end the same way)

1. **A path tool.** Draw the river as a line of squares (click, drag, or click the two ends and let Mirror route it), then **Apply**: Mirror makes those squares river, works out each one's four-side combination, picks the tile, and re-resolves
   the neighbours that changed (the squares beside it, a coast that now meets a river, the tile it replaced). Remove a river the same way (the squares go back to grass, tile 162 as in Paint type, and their neighbours update).
2. **A river layer** in Mirror: rivers are drawn on their own layer (a smooth line, not bound to the tile grid) and Mirror translates the layer to tile numbers on Apply. This is where **Kevin's own art** (STORY-063) helps: with our own tiles a river
   can be drawn as a smooth painted strip, and only the save needs the 4-connected tile version.

They share the core: a function from "a set of river squares" to "tile numbers for those squares and their neighbours". **Build that core first** (pure, tested against real maps: take every river in a real save, recompute its tiles from the squares alone,
and compare with what the game stored); the path tool is the smallest user interface on top of it, and the layer can follow.

## Things to settle or check

- **What a river may replace.** Forest, desert, hills, mountains? *Guess:* the game's own maps put rivers through plain land, forest and swamp; check what terrain sits beside and under real rivers before allowing more. A river through a mountain or a node is probably refused.
- **Lakes and mouths.** A river must end in the sea, a lake, or off a spring; the combinations above allow all of that. Do rivers need to end anywhere at all? (A spring with no mouth is a one-side tile, so allowed.)
- **Landmass ids.** Rivers count as land in the landmass layer ([classic-terrain-format.md](../reference/classic-terrain-format.md)); a river square on a former ocean or coast square joins or splits landmasses. Reuse the rule Paint type uses, as one undo step.
- **Cities, roads, units on a changed square** (as Paint type handles them).
- **Real-game check** (AGENTS.md section 9): load an edited save in DOSBox, see the river drawn right, End Turn, and check the game does not re-tile or reject it.

## Definition of done (for the core and the path tool)

- Tests: the core reproduces every real river tile from the squares (a real-save test, skipped without the save), plus synthetic cases for a straight, a bend, a junction, a mouth, a removal and a refused square.
- The tool applies as one undo step, with the landmass layer kept right.
- Checked in the real game.
