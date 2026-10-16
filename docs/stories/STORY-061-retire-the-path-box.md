# STORY-061: Retire the path box and the old save-path rules

**Parent:** [EPIC-012](../epics/EPIC-012-open-and-save-from-the-browser.md)
**Status:** done (2026-10-16), on Kevin's say-so ("let's get rid of that Lab path box")
**Size:** small

## What to do

Once the slot flow has proved itself in daily use, remove the path box, `MIRROR_MOM_PATH`'s role as "where saves live" (it stays for the LBX files), the "next free slot" suggestion, `SaveFile.write/3`'s overwrite refusal and their tests, and update the README and AGENTS.md. Safari and Firefox users lose the path box too: the README says Chrome or Edge is needed to open and save (Kevin: others at their own risk).
Do this only on Kevin's say-so; until then the path box stays as a fallback.

## What was removed (2026-10-16)

- The Lab page's load and save-path boxes, and `load_save`, `save_file`, `update_load_path` and `update_save_path` in `MapLive` (with their assigns and forms). The map page's own copies had already gone with the redesign.
- `SaveManager`: `load/2` (by path), `save/2`, `normalize_path/1`, `default_load_path/0`, `suggested_save_path/1`, `saved_message/1`, `load_error_message/2`, `save_error_message/1`, and the path form of `start_engine_session/1`.
- `SaveFile`: `write/3` (with the overwrite refusal by path and by inode, the `.bak` copy and the atomic write), `next_free_slot/1` and `game_loadable_name?/1`. `SaveFile.load/1` stays: tests, scripts and the engine's own loader read files with it.
- Their tests (`write_test.exs`, `slots_test.exs`, `map_load_path_test.exs`, the path tests in `save_manager_test.exs`). The map tests now open and save through `MirrorWeb.SaveHelpers` (`open_save/2`, `save_to/2`), which is what the browser does.
- Kept: `MIRROR_MOM_PATH` (where the LBX files are read from), `SaveFile.from_binary/2`, `SaveManager.load_bytes/3`, `slot_bytes/1`, `mark_saved/3`.
- One behaviour moved: the map used to drop its picked unit, lair or node when a save was loaded from its own box. It now does so when the session's save changes under it for any reason (another tab opened one): `drop_picks_for_another_save/3`.

Other browsers (Firefox, Safari) can no longer open a save at all; the README and the start page say so.
