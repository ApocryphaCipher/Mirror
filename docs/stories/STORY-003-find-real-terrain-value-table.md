# STORY-003: Find or derive the complete real terrain-value table

**Parent:** [../epics/EPIC-003-terrain-value-classification.md](../epics/EPIC-003-terrain-value-classification.md)
**Status:** done 2026-09-22. The table is `TERRAIN.LBX` entry 1: save value →
tile record, per plane. Values are tile numbers, not types. Written up in
[../reference/classic-terrain-format.md](../reference/classic-terrain-format.md), found via the GOG release
(`TERRAIN.LBX` was missing from `MAGIC.zip`).
**Size:** unknown — the cheap 20-minute lead (`Terrstat.lbx`) is ruled out
(see below), so this is more likely a multi-session research task now
**Blocks:** STORY-004 (river/volcano/node classification), STORY-001
(shoreline re-verification)

## The question

What does a raw terrain tile value (a `u16`, though evidence so far
suggests only the low byte or thereabouts matters — see caveats) actually
mean, across its full real range? Mirror's current 16-entry table is
provably wrong: it's missing river/river-mouth/volcano/node types
entirely, and a second independent source (`momedit`, see
[../reference/momedit-source/](../reference/momedit-source/)) classifies terrain via ranges over
the **full 16-bit value** (`value < 0x40` = ocean; tundra includes `0x25a`
= 602, which can't fit in a byte), not a clean byte or nibble split.

`momedit` doesn't give a complete table — it only implements 3 of ~16
types, Alpha-quality, one of the three is even buggy. So the real table
still needs to come from somewhere.

## Where to look, cheapest first

1. ~~**`Terrstat.lbx`**~~ — **checked, dead end.** 2 entries: a 770×6 image
   (almost certainly a decorative icon strip — 4,624 bytes ≈ 770×6 pixels,
   1 byte/pixel) and a 1×196 image. The 1×196 shape looked promising
   (one row per lookup entry), but decoded to only 6 distinct **raw
   palette indices** (`[0, 1, 2, 3, 4, 254]`, checked by inverting the
   palette lookup, not just eyeballing colors) — a small per-type stat
   array (movement cost or similar, `254` likely a section-break
   sentinel), not a 196-entry type table. Also reconfirmed: `Mirror.LBX`'s
   `:auto`/`:default` palette resolution produces near-black garbage here
   too, same as the earlier `Compix.lbx` problem — a real, separate bug
   worth its own story under EPIC-002 (raw LBX art can't be trusted until
   palette resolution is fixed, independent of this terrain-value
   question).
2. **More classic-MoM community modding resources.** The pattern that's
   worked all session (wiki for save offsets, `momedit` for cross-check):
   there may be a more complete reference than either of those. Look for
   other classic-save editors/tools, or dedicated "map format" writeups
   beyond the Fandom wiki's `Save_Game_Format` page (which didn't cover
   terrain value semantics — only block offsets).
3. **Empirical correlation.** `Mirror.Stats` already has a bit/value-naming
   mechanism (`set_value_name/4`, `set_bit_name/4`) built and never used
   (see `docs/notes/2026-09-22-repo-recon.md`). If no authoritative source
   turns up, the fallback is: load a save, compare Mirror's raw-value
   histogram against either (a) the actual DOS game running (if Kevin has
   a way to run it) or (b) careful reasoning from known constraints (ocean
   is by far the most common value and should be low/simple; rivers are
   comparatively rare; etc.) — slower and lower-confidence than a real
   source, last resort.

## Constraints to design against

- Raw values in `SAVE1.GAM` span 0–252 (measured), not 0–15.
- No clean nibble split (low-nibble vs high-nibble pairing showed every
  low-nibble value co-occurring with nearly every high-nibble value — not
  type+variant).
- Whatever the scheme is, it needs to resolve to (at least) the real
  game's 16 base types: Mountain, Hills, Forest, Desert, Swamp,
  Grasslands, Tundra, Shore, Ocean, River, Shore (river mouth), Grasslands
  (Sorcery Node), Forest (Nature Node), Volcano/Mountain (Chaos Node),
  River Mouth (landside), Volcano (raised) — this list is already
  confirmed from the real MOMIME production database
  (`docs/reference/momime-source/`), which is a faithful behavioral port of
  the classic game, so there's no reason to expect the classic byte
  scheme names/covers anything different.

## Definition of done

A documented mapping (ideally exhaustive over observed values, at minimum
covering all 16 real types) from raw tile value → terrain type, written up
in `docs/reference/` with its source cited, ready to wire into both
`Mirror.Map`/`Mirror.Quality.ShoreMask` and `map_hooks.js`.
