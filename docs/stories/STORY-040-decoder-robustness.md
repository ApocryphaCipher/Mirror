# STORY-040: Decoders that raise, or accept malformed data, on bad input

**Parent:** [EPIC-008](../epics/EPIC-008-keeping-the-lights-on.md)
**Status:** **Done** (2026-09-25)
**Size:** small to medium

AGENTS.md §7: decoders return `{:ok, _}` / `{:error, _}` and never raise
on bad data. The review found these, each with a synthetic case:

- `TerrainLbx.decode/2` accepts an undersized minimap table, then
  `payload/1` raises.
- City names can be invalid UTF-8 (a `0xFF` byte parses) and would reach
  LiveView's JSON. Whether that actually breaks anything is unverified.
- `LBX` RLE: a trailing repeat marker with no value decodes as a pixel
  instead of an error.
- `Blocks.put_plane_slice/4` raises on a truncated destination.
- `Engine.Fog`: bitsets for map sizes not divisible by 8 raise on update.
- `Engine.MapOps`: a wrapped radius walk counts repeated tiles, and stops
  early.
- Stats export: tuple keys can't be JSON-encoded. The end-to-end failure
  is unverified.

## Outcome

All seven claims were confirmed in the code before fixing, and each has a
synthetic test:

- `TerrainLbx.check_minimap/1` makes `decode/2` return
  `{:error, :short_minimap}`.
- City names are read as Latin-1, so they're always valid UTF-8.
- `LBX.expand_rle/2` returns `{:error, :truncated_rle}` for a trailing
  repeat byte, and `decode_runs` passes the error on.
- `Blocks.put_plane_slice/4` returns `{:error, {:short_binary, layer}}`.
- `Engine.Fog` stores bitsets padded to whole bytes, and pads unpadded
  ones (`Engine.Session` makes those) instead of refusing them.
- `Engine.MapOps` walks each tile once, using a visited set. On a wrapped
  3 × 8 map, radius 5 now visits all 24 tiles, not 15; the tests fail on
  the old code.
- `Stats.format_key/1` makes export keys and the dataset id JSON-safe.

Drafted by the team's NUC (Qwen3.8, about a minute per brief). Claude's
corrections:
- syntax errors in the tests;
- a hallucinated bitwise API (`Bitor.bor`);
- `rem` for `Integer.mod` in the wrap, which would break west and north
  wrapping;
- underscored variables it then used.

## Done when

Each case has a synthetic test: an error is returned (or the output is
correct), with no raise.
