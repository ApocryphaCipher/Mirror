# EPIC-003: Fix terrain value classification (the real root cause under rivers + the shoreline)

**Status:** scoped, not started
**Owner:** Kevin
**Found:** 2026-09-22, while investigating Kevin's report that rivers/towns/
forts/towers/tombs don't render and the shoreline still looks "saw-tooth"
after PR #3/#4.

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

### STORY: Stop the circular auto-detect heuristic
Small, immediate. Remove or gate `detectTerrainBaseSource()`'s scoring
against the current lookup table (or just delete it and hardcode full-value
reads, matching what's actually correct once STORY below lands). Cheap, but
don't expect it to fix anything on its own — it just stops actively hiding
the real gap.

### STORY: Find or derive the complete real terrain-value table
The actual research task. Options, roughly cheapest-first:
1. Decode `Terrstat.lbx` (5,400 bytes, in `~/.mirror_assets/MAGIC`) — name
   suggests "terrain stats," never actually inspected this session. Could
   be exactly the value→type table, or per-type stats keyed by a smaller
   type ID (worth 20 minutes before anything else).
2. Check other classic-MoM community modding tools/docs beyond momedit and
   the Fandom wiki (the pattern that's worked all session: go find primary
   sources instead of reverse-engineering blind).
3. Empirical derivation: use `Mirror.Stats`' existing bit/value-naming
   tooling (already built, never used — see the 2026-09-22 recon notes) to
   correlate raw values against the in-game minimap/actual screenshots
   Kevin can provide from the real game running.

### STORY: Add river/river-mouth/volcano/node kinds once the table is known
Wire the corrected table into both `Mirror.Map`/`Mirror.Quality.ShoreMask`
(Elixir) and `map_hooks.js` (JS, the one that actually renders). River
smoothing uses `SS16` per the real MOMIME ruleset (already ported in PR #4)
— the `overland/terrain/{plane}/river/` art is already sitting in
`resources/` from the PR #4 work, just currently unreachable because no
tile ever classifies as `"river"`.

### STORY: Re-verify the shoreline after the terrain fix lands
Don't re-litigate PR #4's algorithm — re-run the same
`fallbackStep`-counting check plus a fresh native-resolution canvas crop
(same method used in PR #4) once terrain classification is fixed, to see
how much of the saw-tooth look was actually this bug. Closes or reopens
STORY-001 depending on the result.

## Dependency note for EPIC-004

Cities/towers/lairs live in *separate* save-file data blocks, not the
terrain layer — EPIC-004 doesn't strictly depend on this epic. But a
correct terrain-value table makes drawing city/feature markers *in the
right visual context* (e.g., not on top of a misclassified tile) more
trustworthy, so doing this first isn't wasted even for that epic.
