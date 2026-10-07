# STORY-044 (bug): Cities/units/sites overlays go stale on cross-tab save updates

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** fixed 2026-10-06.
**Size:** small–medium
**Reported by:** Copilot's PR review on
[#74](https://github.com/ApocryphaCipher/Mirror/pull/74) (STORY-011),
confirmed by Claude 2026-09-27.

## Symptom

Open the same session in two tabs (or two windows on the same
`session_id`). Load a different save, discard edits, or anything else
that goes through `SessionStore.update/2` in one tab. **The other tab's
cities, units and sites overlays keep showing the previous save's data**
— only `settleable`/`roads`/`fog` (and the terrain itself) refresh there.
A page reload fixes it.

## Confirmed root cause

`push_overlays/1` (`map_live.ex`) is the only place that pushes the
`"cities"`, `"units"` and (since STORY-011) `"sites"` `overlay_data`
events, and it's called from exactly one place: `maybe_push_tile_assets/1`,
itself only reached from the *local* handlers that change `state` directly
(`load_save`, `discard_edits`'s own branch at the call site, tile
edits...).

`handle_info({:session_state_updated, ...}, socket)` — the cross-tab sync
path, fired via `Phoenix.PubSub` whenever *any* tab on the session calls
`SessionStore.put/2` or `update/2` (21 call sites in `map_live.ex`) — calls
only `push_map_state() |> push_map_reload() |> push_map_layers()`.
`push_map_layers/1` covers `settleable`/`roads`/`fog` only; it does not
call `push_overlays/1`. Same gap in the `discard_edits` handler's own
socket-update branch (line ~258): also `push_map_layers()`, not
`push_overlays()`.

This predates STORY-011: cities (STORY-010) and units (STORY-012) have
had this exact gap since they shipped. STORY-011 just added a third
layer with the same wiring, which is why Copilot's review caught it here
rather than earlier — nothing in STORY-011 introduced or worsened it.

## Why this isn't a one-line fix

The obvious fix is swapping `push_map_layers()` for `push_overlays()` in
`handle_info/2` (and the `discard_edits` branch) — `push_overlays/1`
already ends with `push_map_layers()`, so it's a superset. **But**
`push_overlays/1` also calls `OverlaySprites.load(Paths.mom_path())`
every time, uncached: a fresh `MAPBACK.LBX` (+ `UNITS1`/`UNITS2`) decode
and palette build, on every call. `SessionStore.update/2` fires on every
edit (paint a tile, move the brush, etc.), broadcast to every other tab.
Naively calling `push_overlays/1` from `handle_info/2` would re-decode
those LBX files, and rebuild every sprite frame, once per edit per other
open tab — a real perf regression for anyone with two tabs open while
editing, not just a correctness fix.

## What to do

1. Split `push_overlays/1`: sprites (`OverlaySprites.load/1`'s result)
   only need pushing once per socket (they never change during a
   session — the game files on disk don't change), separately from the
   per-save `cities`/`units`/`sites` *items*, which do need to follow
   every save change, including cross-tab ones.
2. Add a `push_overlay_items/1` (or similar) covering `cities`, `units`,
   `sites`, call it from `handle_info/2` and the `discard_edits` branch
   alongside `push_map_layers/1`, and drop the sprite reload from that
   path entirely (assign the decoded sprites once, e.g. in
   `maybe_push_tile_assets/1`'s first connect, and skip re-pushing them
   from the hot per-edit path — mirrors how `push_tile_assets/2` already
   has a `clear_cache?` guard for exactly this reason).
3. Add a test: two `live/2` views on the same `session_id`, load a save
   (or discard) in one, `assert_push_event` the `"cities"`/`"units"`/
   `"sites"` `overlay_data` in the *other*.

## Definition of done

- A second tab on the same session shows the new save's cities, units
  and sites immediately, without a reload.
- No `OverlaySprites.load/1` call added to a path that fires on every
  tile edit.

## Fix

`push_overlays/1` is split: it still decodes the sprites once (the load path)
and calls the new `push_overlay_items/1`, which pushes `sites`, `cities` and
`units` from the save's raw bytes. The cross-tab `handle_info/2` and the
`discard_edits` branch now call `push_overlay_items_if_save_changed/2`: the items
depend only on `save.raw` and the plane, so they are pushed again only when the raw
save differs from the one the tab had. A tile edit in another tab leaves it alone,
so no sprite decode and no items re-push on the per-edit path.

Tests (`map_live_edit_test.exs`, "overlays follow the save across tabs"): a save
loaded in one tab reaches the other's cities, units and sites; a different save
replaces them; and a tile edit pushes neither `overlay_sprites` nor the items. All
three fail without the fix.
