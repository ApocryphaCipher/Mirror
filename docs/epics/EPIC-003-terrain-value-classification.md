# EPIC-003: Fix terrain value classification (the real root cause under rivers + the shoreline)

**Status:** resolved 2026-09-22 — the "missing table" is `TERRAIN.LBX` itself: terrain values are tile numbers, not types. See [../reference/classic-terrain-format.md](../reference/classic-terrain-format.md). Code fix folds into EPIC-002's STORY-005.
**Owner:** [Kevin](https://github.com/KevinAsbury)
**Found:** 2026-09-22, while investigating Kevin's report that rivers/towns/
forts/towers/tombs don't render and the shoreline still looks "saw-tooth"
after PR #3/#4.

## Resolution (2026-09-22)

Every hypothesis below was circling the right problem from the wrong end.
The raw `u16` isn't a type code with some unknown encoding — it's an index
(0–761 per plane) into the game's own tile table. momedit's odd-looking
ranges (`< 0x40` = ocean, tundra = `0xA7`, `0x25A`, …) are just "which tile
numbers happen to depict ocean/tundra". Rivers were never missing from the
data; they're ordinary tile numbers Mirror truncated to a low byte and then
mis-typed.

Story outcomes:

- STORY-002 — rescoped: stop the heuristic *and* read the full `u16` (not
  low byte). Folded into STORY-005.
- STORY-003 — done: the table is `TERRAIN.LBX` entry 1.
- STORY-004 — obsolete for rendering: rivers/volcanoes/nodes are just tiles.
- STORY-001 — obsolete on the `TERRAIN.LBX` path.

The original investigation is kept below for the record.

---

## Why this is its own epic, not a bullet under EPIC-001

EPIC-001 (PR #3, PR #4) fixed the *rotation/smoothing algorithm* — that part
is verified correct against the real MOMIME rule table. What this
investigation found is a layer **underneath** that: the raw per-tile value
Mirror reads out of the save file is being misinterpreted before the
smoothing algorithm ever sees it. If this is wrong, no amount of smoothing-rule
correctness fixes rivers, cities, or a truly correct shoreline — garbage in,
garbage out.

## The bug, concretely

`assets/js/map_hooks.js` has a `detectTerrainBaseSource()` routine that
auto-picks how to extract a "terrain type" number from each tile's raw u16
value — full low byte (`value & 0xff`), full high byte, or either byte
truncated to just its low nibble (`& 0x0f`). It scores each option by how
many resulting values match entries in `TERRAIN_KIND_BY_BASE_ID`, a
**16-entry** lookup table.

This is circular: `lo_nibble` can only ever produce 16 possible outputs, so
it trivially scores ~100% "known" against a 16-entry table, while the full
byte (0–255 possible values) correctly reports most values as unrecognized
— not because the full byte is wrong, but because the table is incomplete.
The heuristic then "resolves" this by picking the option that throws away
the most information. Confirmed live against the real save: `lo_nibble` is
currently selected, discarding real data.

Measured on `SAVE1.GAM`: raw per-tile byte values actually span **0–252**
(not 0–15). Grouping by nibble shows no clean type+variant split — pairing
every low-nibble value with nearly every high-nibble value — so it's not
simply "low nibble = type, high nibble = variant" either. Something else is
going on.

## What a second, independent source says

Pulled the source of `momedit` (Master Of Magic Game Editor, GPLv2, real
working classic-save editor — see
[../reference/momedit-source/](../reference/momedit-source/)). Its terrain classification
(`MiniMap.cs`) works on **ranges over the full 16-bit raw value**, not a
byte or nibble split at all:

```csharp
public bool IsOcean(...) { return (f < 0x040) || Contain(oceanFields, f); }
private static short[] tundraFields = { 0xb5, 0xb6, 0xa7, 0x25a, 0x263, 0x25f };
```

`0x25a` = 602 — doesn't fit in a byte, so the real scheme can't be
byte-level at all; it's over the full short. This directly contradicts both
Mirror's current byte/nibble approach *and* the Elixir side's assumption
(`terrain_type(value) = value &&& 0xFF`, low byte only — also likely wrong,
just less obviously so, and inconsistent with what the JS side does today
regardless).

**Important limitation**: momedit is Alpha-status and only implements 3 of
the real ~16 terrain types (Ocean, Tundra, and a buggy Grassland check that
actually reads the wrong field). It does *not* give us a complete
value → type table. It gives strong evidence Mirror's current model is
wrong, not the fix itself.

## Why this explains what Kevin saw

- **Rivers never render**: Mirror's 16-entry kind table has no "river" or
  "river mouth" entry at all — it repeats ocean/shore/land types twice
  instead. Even if the extraction method were fixed, river tiles would
  still have nowhere to land in the classification.
- **Saw-tooth shoreline**: if terrain type classification is wrong for even
  a modest fraction of tiles near coastlines, the (now-correct) smoothing
  algorithm computes locally-wrong masks from locally-wrong neighbor kinds,
  producing exactly the kind of small, regular-looking edge artifacts Kevin
  is seeing. The PR #4 fix could be completely correct and this would still
  look bad, because it's a different bug in a different layer.

## Stories

- [STORY-002](../stories/STORY-002-stop-circular-terrain-source-heuristic.md) — stop the circular auto-detect heuristic (small, ~30–60 min, but low value alone — see the story for why it's best paired with STORY-003)
- [STORY-003](../stories/STORY-003-find-real-terrain-value-table.md) — find or derive the complete real terrain-value table (the actual research task; size unknown, cheapest lead is decoding `Terrstat.lbx`)
- [STORY-004](../stories/STORY-004-add-river-volcano-node-kinds.md) — add river/river-mouth/volcano/node kinds once the table is known (blocked on STORY-003; mechanical once unblocked, since the algorithm and art already exist from PR #4)
- [STORY-001](../stories/STORY-001-jagged-shorelines.md) (lives under EPIC-001, blocked here too) — re-verify the shoreline once STORY-003/004 land, using the same `fallbackStep`-counting + native-resolution-crop method from PR #4

## Dependency note for EPIC-004

Cities/towers/lairs live in *separate* save-file data blocks, not the
terrain layer — EPIC-004 doesn't strictly depend on this epic. But a
correct terrain-value table makes drawing city/feature markers *in the
right visual context* (e.g., not on top of a misclassified tile) more
trustworthy, so doing this first isn't wasted even for that epic.
