# 2026-09-23 (evening): Handoff, start here

Read [../../AGENTS.md](../../AGENTS.md) first: it has the workflow, the checks, the
game-file rules and the Elixir patterns. This note only covers where things
stand. The earlier [2026-09-23-session-handoff.md](2026-09-23-session-handoff.md) is history.

## Where things stand

Everything is merged to `main` (through #34); nothing is open. `main` is
protected: PR plus a green CI `test` check, no direct pushes.

- **LBX decoding is correct** (`Mirror.LBX`): name tables, the real
  image format, and the `FONTS.LBX` #2 palette. The sprite catalog is in
  [../reference/overland-sprites-and-save-blocks.md](../reference/overland-sprites-and-save-blocks.md).
- **Map pages** have an overlay canvas and a **Layers** panel (STORY-009).
  **Cities** are drawn (STORY-010, fixed in #32 against the real game):
  `MAPBACK #20`, frame = size − 1, flag recoloured to the owner's banner.
- **Setup:** `mix mirror.import_game <install or zip>` fills
  `~/.mirror/game` (the dev server's default `MIRROR_MOM_PATH`).

## Next task: STORY-032 (cities follow-up)

[../stories/STORY-032-cities-walls-labels-verify.md](../stories/STORY-032-cities-walls-labels-verify.md). Its
"Findings" section already answers the hard parts: City Walls is record
`+66`, the size byte runs 0 Outpost / 1 Hamlet / 2 Village, and outposts
seem to have no flag. What's left to do:

1. Parse walls (`+66 == 1`) and pass `walled` to the client.
   Walls don't change the hamlet sprite, so this is data for later.
2. Outposts (size 0): find their sprite (maybe `#21` `CITYNOWA`?) and drop
   the flag, checked against the screenshots.
3. City names in the hover readout.
4. Check the rival and neutral flag colours in the screenshots.

After that, EPIC-004's order: STORY-012 (units + plaques), STORY-011
(sites), STORY-013 (roads/specials), STORY-008 (node auras).

## Checking against the real game

- DOSBox 0.74-3 (`/Applications/DOSBox.app`). Its default config
  mounts `/Users/kevin/DOS` as `C:` (`cd MAGIC`, then `magic`).
- `~/DOS/MAGIC/SAVE3.GAM`, "Freya - God mode", is SAVE1 with 30,000
  gold and mana (wizard `+0x356` / `+0x25c`). Slots 4–9 are Kevin's
  checkpoint saves. Their window shots (with timestamps) are in
  `~/.mirror/dev/DOSbox/FREYA - God Mode/`.
- Diff city records between saves first, then look at the few
  screenshots that matter. Contact sheets (PIL) beat opening 58 images.
  Screenshot filenames have a narrow no-break space before "PM", so
  match them with a glob.
- Game quirk: loading SAVE1 renames the starting city ("Name Starting
  City"), so don't cross-check by city name.

## Watch out

- **Something syncs this checkout and can undo work.** It renames files
  to `… [conflicted N]` (in `.git`, and `_build/…/.mix/compile.elixir`,
  which makes Phoenix demand a restart and the compiler print "redefining
  module"), and it once deleted a tracked file after a pull. Commit and
  push often, check `git status` for unexpected ` D` lines, and if the
  reloader complains:
  `find _build -name '*\[conflicted*' -delete && mix compile --force`,
  then restart. The cause is still unknown (not iCloud, Dropbox or Google
  Drive).
- Running the dev server writes `priv/mirror_stats.dets`. Don't commit
  it (`git checkout -- priv/mirror_stats.dets`).
- Open proposals waiting on Kevin: delete the dead
  `Mirror.Quality.SmoothingRules`, and remove the stray root `proposal.md`.
