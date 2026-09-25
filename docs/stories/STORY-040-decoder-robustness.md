# STORY-040: Decoders that raise, or accept malformed data, on bad input

**Parent:** [EPIC-008](../epics/EPIC-008-keeping-the-lights-on.md)
**Status:** open, P2
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

## Done when

Each case has a synthetic test: an error is returned (or the output is
correct), with no raise.
