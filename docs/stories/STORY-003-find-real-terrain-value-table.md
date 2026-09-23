# STORY-003: Find or derive the complete real terrain-value table

**Parent:** [../epics/EPIC-003-terrain-value-classification.md](../epics/EPIC-003-terrain-value-classification.md)
**Status:** open — research spike, the actual hard part of this epic
**Size:** unknown — could be 20 minutes (if `Terrstat.lbx` is exactly this
table) or multi-session (if it requires empirical correlation against a
running game)
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

1. **`Terrstat.lbx`** (`~/.mirror_assets/MAGIC/Terrstat.lbx`, 5,400 bytes).
   Never actually inspected this session — the name ("terrain stats")
   strongly suggests this could be exactly the value→type table, or a
   per-type stats table keyed by a smaller type ID that the raw value maps
   into. Use the Tile Bit Inspector (`/tile-probe`) or a quick throwaway
   script against `Mirror.LBX` to look at its raw structure. Cheapest
   possible next step — do this first.
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
