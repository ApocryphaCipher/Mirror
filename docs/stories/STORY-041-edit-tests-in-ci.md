# STORY-041: Editing and save-safety tests are all skipped in CI

**Parent:** [EPIC-008](../epics/EPIC-008-keeping-the-lights-on.md)
**Status:** open, P2
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

## Done when

`mix test` in CI runs the editing and save-safety tests, including
STORY-038's new ones, with no game files present.
