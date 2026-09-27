# STORY-041: Editing and save-safety tests are all skipped in CI

**Parent:** [EPIC-008](../epics/EPIC-008-keeping-the-lights-on.md)
**Status:** **Done** (2026-09-26)
**Size:** medium

`test/mirror_web/live/map_live_edit_test.exs` needs the real `SAVE1.GAM`,
so the whole module is skipped in CI. That module covers editing, undo,
discard, Save as and the Surveyor card. The most dangerous code in Mirror
is therefore tested only on Kevin's machine.

Build a **synthetic save** in the test: a save-sized binary with a known
terrain, cities and sites, like `cities_test.exs` and `surveyor_test.exs`
already do. Move the editing, history, overwrite-protection and
round-trip tests onto it. Keep a few real-file tests, tagged and
skippable (AGENTS.md §10).

Also say in AGENTS.md and README that the Surveyor's real-save tests read
`MIRROR_SURVEYOR_SAVE` (a frozen save outside the repo), which
`scripts/test_game.sh` doesn't set. And say plainly that today's terrain
editor does **not** keep the landmass IDs consistent (see STORY-017/029).

## Outcome

1. Implemented `synthetic_save_bytes/0` in `test/mirror_web/live/map_live_edit_test.exs`,
   generating a full 123,300-byte classic save fixture with known terrain, cities,
   wizards, and sites blocks.
2. Removed module-level `@moduletag skip: ...` from `MapLiveEditTest`. 24 tests
   covering editing, history/undo/redo, multi-tab sync, discard, Save as overwrite
   protection, Surveyor card, and settleable/fog overlays now run unconditionally
   in CI without requiring game files or environment variables.
3. Retained 3 real-save integration tests in a dedicated `describe "real-save integration"`
   block, tagged with `@tag skip: !@has_real_save && ...` so they execute when
   `MIRROR_MOM_PATH` and save offsets are present.
4. Documented in `AGENTS.md` and `README.md` that the Surveyor's real-save tests
   read `MIRROR_SURVEYOR_SAVE` (which `scripts/test_game.sh` does not set, requiring
   a manual export or fixture placement).
5. Documented in `AGENTS.md` and `README.md` that today's terrain editor updates
   terrain bytes and recomputed adjacency masks only, and does **not** keep
   landmass/continent IDs consistent across land/water transitions (tracked in
   STORY-017 and STORY-029).

## Done when

`mix test` in CI runs the editing and save-safety tests, including
STORY-038's new ones, with no game files present.
