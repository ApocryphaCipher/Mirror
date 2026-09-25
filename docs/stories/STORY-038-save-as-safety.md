# STORY-038: Save as can overwrite the loaded save (and other save-safety gaps)

**Parent:** [EPIC-008](../epics/EPIC-008-keeping-the-lights-on.md)
**Status:** **Done** (2026-09-25): items 1–5 in #62, item 6 in #63
**Size:** small to medium

AGENTS.md §9: never overwrite the save that was loaded. Today that can
happen. Findings from the
[review note](../notes/2026-09-24-ktlo-review.md#code-review-lib-test-assetsjs-scripts):

1. **Empty path after an earlier Save as overwrites the loaded file.**
   *Verified by Claude.* `guard_original/3` compares the target with
   `state.save_path` (the previous Save as target), but
   `SaveFile.write(save, nil)` falls back to `save.path`, the loaded file
   (`map_live.ex` `handle_event("save_file")`, `guard_original/3`;
   `save_file.ex` `write/3`). Fix: resolve one destination, and use it
   for both the check and the write.
2. **The wrong file is backed up.** *Verified by Claude.* Saving to a
   different, existing file backs up the *source* as `<target>.bak`, so
   the destination's old contents are lost (`save_file.ex`
   `maybe_backup/3`). Fix: back up the destination, or refuse to
   overwrite an existing destination.
3. **The Lab skips the guard** (`guard_original/3`, `lab?`). Decide
   whether the Lab really needs that. Safer: enforce the rule in
   `SaveFile.write/3` for every caller.
4. **The path comparison is by string:** symlinks, hard links or a
   different letter case (macOS is case-insensitive) get past it. Compare
   file identity (`File.stat` inode and device) instead.
5. **The write isn't atomic:** a failed write can leave a truncated save.
   Write a temporary sibling file, then rename it.
6. **When all nine slots exist, the suggestion is `*-edited.GAM`,** which
   the game can't load. Say so, and ask for another folder.

## Outcome (items 1–5)

`SaveFile.write/3` enforces the rule itself, for every caller, the Lab
included:
- A destination is required.
- The loaded file is refused by path and by inode+device (symlinks and a
  different letter case included).
- An existing destination is backed up.
- The write goes to a temporary file that's renamed over the target.

`MapLive` lost its string-comparison guard. An empty path now means
"where I last saved", which is refused before any Save as.
`test/mirror/save_file/write_test.exs` covers it: 7 tests, 5 of which fail
on the old code. Drafted by the team's NUC (Qwen3.8), reviewed and
corrected by Claude.

## Outcome (item 6)

When all nine slots are taken, Save as suggests nothing instead of an
unloadable `*-edited.GAM`. Saving under any other name still works, with
a flash saying the game only loads `SAVE1`–`SAVE9.GAM`.
`SaveFile.next_free_slot/1` and `game_loadable_name?/1` have 7 tests.
Drafted by the NUC in 57 s.

## Done when

Each case has a test that fails without the fix: an empty path after
Save as, an existing destination, the Lab, a symlinked or re-cased path,
and a failed write. `SaveFile.write/3` refuses to write the loaded file
whoever calls it.
