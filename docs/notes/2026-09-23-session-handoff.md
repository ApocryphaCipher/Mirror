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

## Next task: STORY-006, sprite groundwork

[../stories/STORY-006-sprite-groundwork.md](../stories/STORY-006-sprite-groundwork.md). It's the critical path:
cities (010), units and plaques (012), sites (011), specials and roads
(013), node auras (008) and safe editing (029) all wait on it.
Survey so far: [../reference/overland-sprites-and-save-blocks.md](../reference/overland-sprites-and-save-blocks.md).

Smaller alternatives: STORY-007 (ocean twinkle), STORY-024 (hover
highlight).

## Dev setup

- Game files live outside the repo (copyrighted; never commit them):
  - `~/.mirror_assets/MAGIC`: the old CD-era install plus the saves
    (`SAVE1/2/9.GAM`). `TERRAIN.LBX` was copied in from GOG; its
    `Fonts.lbx` is byte-identical to GOG's.
  - `~/.mirror_assets/GOG`: so far only `TERRAIN.LBX`, `FONTS.LBX`,
    `MAIN.LBX` and `render_map.py`. **The full GOG install is on Kevin's
    Google Drive** (folder "Master of Magic Official Release"). Pull the
    rest of the LBX files from there (the Drive connector saves big files
    to disk; decode with `jq -r .content … | base64 -d`).
- Run the app: `bash scripts/dev_server.sh` (port 4000). Load
  `~/.mirror_assets/MAGIC/SAVE1.GAM` via the header's Load box.
- Tests: `mix test` skips the real-file tests; **`bash scripts/test_game.sh`**
  runs everything with the game-file env (35 tests).
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
- **LBX files** have a readable name table at `0x200` (32-byte rows). Images
  in `TERRAIN.LBX` and the cursors are column-major; the palette is
  `FONTS.LBX` entry 2, 6-bit VGA (scale 255/63).
- **The dev server runs from a previous session** (unnamed node) and
  live-reloads. Kevin's session state lives in its ETS; don't leave test
  edits behind (undo or discard them).

## Working agreement with Kevin

- Push branches and open PRs without asking; Kevin merges. Never enable
  auto-merge.
- Ground claims in the real files (render it, hash it, test it) before
  writing them into docs or tickets; mark guesses as guesses.
- Kevin likes tickets for ideas that come up mid-task: write them in
  `docs/stories/`, link them from the epic and the stories index.
