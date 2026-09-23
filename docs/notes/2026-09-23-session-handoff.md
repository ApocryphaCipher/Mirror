# 2026-09-23: Session handoff (start here next time)

## Where things stand

All work is merged to `main` (PRs #3–#23); nothing is open.

- **Terrain renders straight from `TERRAIN.LBX`.** A save's u16 terrain
  value is a tile number: [../reference/classic-terrain-format.md](../reference/classic-terrain-format.md). The MOMIME
  path is gone.
- **Map pages** (`/arcanus`, `/myrror`): Google-Maps-style view mode (fit,
  wheel zoom, drag pan, hover readout) plus an **edit mode** (✎ Edit /
  Done / Esc) with 🔄 **Cycle** (click = next tile number, right-click =
  previous) and 🎨 **Paint** (stamp a brush tile), Undo/Redo, an
  "N tiles changed" counter, two-step Discard, and Save as (suggests the
  next free `SAVEn.GAM`, refuses the loaded file).
- **`/lab/:plane`**: research workbench (raw layers, bit/value labelling,
  histograms, raw painter). **`/tile-probe`**: LBX explorer.
- The stories index is [../stories/README.md](../stories/README.md); epics are in [../epics/](../epics/).

## Next task: pick an overlay story (STORY-006 is done)

STORY-006 landed the sprite catalog:
[../reference/overland-sprites-and-save-blocks.md](../reference/overland-sprites-and-save-blocks.md). Cities, plaques,
units, sites, specials, roads and sparkles are mapped to `FILE.LBX #entry/frame`.
`Mirror.LBX` decodes all of them correctly now. Next up, each needs its
save block decoded first: STORY-009 (layer toggles), then STORY-010
(cities) → STORY-012 (units + plaques) → STORY-011 (sites) → STORY-013
(roads/specials), and STORY-008 (node auras).

Smaller alternatives: STORY-007 (ocean twinkle), STORY-024 (hover
highlight).

## Dev setup

- Game files live outside the repo (copyrighted; never commit them).
  `mix mirror.import_game <install folder or zip>` copies the five LBX files
  Mirror reads, plus the saves, into **`~/.mirror/game`**, which is the dev
  server's default `MIRROR_MOM_PATH`. Kevin's full copies:
  `~/.mirror_assets/GOG` (61 GOG LBX files) and `~/.mirror_assets/MAGIC`
  (old CD-era install + original saves).
- Run the app: `bash scripts/dev_server.sh` (port 4000). The Load box
  defaults to `~/.mirror/game/SAVE1.GAM`.
- Tests: `mix test` skips the real-file tests; **`bash scripts/test_game.sh`**
  runs everything with the game-file env (50 tests).
- Reference renderer: `python3 scripts/mom_map_render.py SAVE1.GAM --lbx ~/.mirror_assets/GOG`.

## Gotchas learned the hard way

- **The Claude in-app browser answers `window.confirm()` with `false`
  instantly** (no dialog). Never use `data-confirm`; use in-page confirms.
- **zsh doesn't word-split `$VAR`**, so `env $VARS mix test` silently
  passes one argument. Use `scripts/test_game.sh`.
- **`push_event` returns a new socket.** Discarding it silently drops the
  event (that was STORY-023).
- **Anything above the map that changes size shifts the map under the
  pointer**, so clicks hit the wrong tile. Keep toolbars and notices as
  overlays.
- **Stacked PRs:** don't target another PR's branch (#8 merged into a stale
  branch and never reached `main`). Branch from it but target `main`.
- **LBX files** have a readable name table at `0x200` (32-byte rows) and
  entry offsets at byte 8. Every image is column-major (RLE for sprites).
  The palette is `FONTS.LBX` entry 2, 6-bit VGA (scale 255/63), with index
  0 transparent. Format details are in the reference doc's "LBX formats".
- **Sessions own their dev server.** Start it with `scripts/dev_server.sh`
  and stop it when you're done. A leftover server from an earlier session
  is a mistake, not [Kevin](https://github.com/KevinAsbury)'s (Kevin, 2026-09-23), so check first:
  `lsof -iTCP:4000 -sTCP:LISTEN`. Session state lives in its
  ETS, so still don't leave test edits in a save you're sharing.

## Working agreement with Kevin

The full version is [../../AGENTS.md](../../AGENTS.md). CI runs on every PR, and `main`
is protected (no direct pushes).


- Push branches and open PRs without asking; Kevin merges. Never enable
  auto-merge.
- Ground claims in the real files (render it, hash it, test it) before
  writing them into docs or tickets; mark guesses as guesses.
- Kevin likes tickets for ideas that come up mid-task: write them in
  `docs/stories/`, link them from the epic and the stories index.
