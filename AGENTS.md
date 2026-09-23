# AGENTS.md

Engineering standards for anyone, human or AI agent, working on **Mirror**:
a Phoenix/LiveView viewer and editor for classic *Master of Magic* save
files. More specific instructions (a story's acceptance criteria, an explicit
request from Kevin) override these when they conflict.

The short version: make the smallest change that solves the task, ground
every claim about the game's formats in the real files, keep the checks
green, and leave the docs truer than you found them.

---

## 1. Done means checked

Work is not complete until these pass:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
bash scripts/test_game.sh   # when the game files are available (see §5)
```

CI runs the first three on every pull request and on `main`
([.github/workflows/ci.yml](.github/workflows/ci.yml)).

Do not weaken, delete or skip a test to get green. Do not suppress a warning
without a written reason. If you couldn't run a check, say so and why.

## 2. Git workflow

- **Never commit to `main`.** Branch, commit, push, open a PR against
  `main`. `main` is protected; CI must pass before merging.
- Branch names: `feat/…`, `fix/…`, `docs/…`, `chore/…`.
- Commit subjects use the same prefixes (`feat:`, `fix:`, `docs:`,
  `chore:`, `style:`) and name the story when there is one
  (`… (STORY-006)`). Keep formatting-only changes in their own commit.
- Agents open PRs without asking; **Kevin merges**. Never enable
  auto-merge, never force-push or rewrite shared history unless asked.
- Stacked work: branch from the earlier branch if you must, but **target
  `main`**. A PR targeting another PR's branch once merged into a stale
  branch and never reached `main`.
- Don't discard or "clean up" changes you didn't make.

## 3. Stay inside the task

Make the smallest coherent change. No drive-by refactors, renames or
reformatting of files you aren't otherwise touching. If you notice something
worth doing that's outside the task, write a ticket (§12) instead of doing it.

Delete dead code rather than keeping it "just in case", but deleting a
module is its own decision. Propose it; don't slip it into an unrelated
change.

## 4. Dependencies

No new Hex or npm dependency without Kevin's approval. Check first whether
Elixir/OTP, Phoenix or an existing dependency already does the job. For
binary formats the answer is almost always "pattern matching already does".

## 5. Game files and copyright

The game's files (`*.LBX`, `*.GAM`, `FONTS.LBX` palettes, anything decoded
from them, `priv/tile_cache/`) are copyrighted. **They must never be
committed**, not even small fixtures cut from them.

- They live outside the repo, under `~/.mirror_assets/` (`GOG/` is the
  complete install and the dev server's `MIRROR_MOM_PATH`; `MAGIC/` is an old
  partial CD install).
- Tests use **synthetic** binaries built in the test (see
  `test/mirror/lbx_test.exs`). Real-file tests read from `MIRROR_MOM_PATH`
  and are skipped when it's missing:

  ```elixir
  @mom_path System.get_env("MIRROR_MOM_PATH", "")
  @tag skip: !File.exists?(Path.join(@mom_path, "MAPBACK.LBX")) && "needs MAPBACK.LBX"
  ```

- Before committing, check the diff for anything that came out of a game
  file.

## 6. Ground truth: don't guess formats

Mirror reimplements undocumented binary formats. Guessing from patterns has
cost this project a lot of wrong turns (see the MOMIME history in
`docs/reference/codex-notes/`). The rules:

- **Ground every format claim in the real files** before writing it into
  code, docs or tickets. Render it and look, hash it, or test it.
- A layout counts as verified with two independent sources, or one source
  plus a visual check against a known save. The game's own data counts as a
  source; a guess from byte patterns does not.
- **Mark guesses as guesses** (*guess:* …) in docs and tickets, and say
  what would confirm them.
- When two decoders disagree, the one you can check against the game's data
  wins. When you replace a decoder, cross-check it against an independent
  implementation (e.g. hash every frame from both).
- Write what you learned into `docs/reference/`, with where it came from.
  The catalog of known sprites is
  `docs/reference/overland-sprites-and-save-blocks.md`; the terrain format
  is `docs/reference/classic-terrain-format.md`.

Python scripts for one-off investigation and cross-checking are fine (and
`scripts/mom_map_render.py` is the reference renderer), but app code is
Elixir.

## 7. Elixir patterns in this codebase

**Binary formats.** Parse with binary pattern matching, not byte-by-byte
index arithmetic:

- Be explicit about endianness and width: `count::little-16`,
  `offset::little-32`.
- Match literal magic values in the pattern
  (`<<count::little-16, 0xFEAD::little-16, …>>`) instead of trying several
  layouts and keeping whichever "looks valid". That heuristic is how
  `Mirror.LBX` came to read every MAPBACK entry off by one.
- Pin variables used in sizes: `<<_::binary-size(^offset), …>>`.
- Guard ranges need a step: `x in 0..(@width - 1)//1`.
- Comprehensions over binaries are the idiom for tables:
  `for <<o::little-32 <- table>>, do: o`.
- Game data is column-major in places (terrain tiles, LBX images). Convert
  to row-major in one clearly named function, not inline.

**Errors.** Files and saves are untrusted input. Decoders return
`{:ok, value}` / `{:error, reason}` and never raise on bad data; chain them
with `with`. A decode failure is an error the caller can show, never
garbage pixels.

**Structure.** Keep format decoding (`lib/mirror/…`: `Mirror.LBX`,
`Mirror.TerrainLbx`, `Mirror.SaveFile`) pure and separate from LiveViews.
LiveViews call into those modules; they don't parse bytes themselves.

**Style.** Small focused functions, names from the game's domain (entry,
frame, plane, tile, banner), piping where it reads naturally. Moduledocs
explain the format being decoded; comments explain *why*, not what.

## 8. LiveView and front-end gotchas

These all bit a previous session:

- `push_event/3` **returns a new socket**. Discarding it silently drops the
  event (STORY-023).
- The Claude in-app browser answers `window.confirm()` with `false`
  instantly. Never use `data-confirm`; build in-page confirmations.
- Anything above the map that changes size shifts the map under the
  pointer, so clicks land on the wrong tile. Toolbars and notices are
  overlays.
- Canvas `ImageData` is RGBA, in that order.

## 9. Saves: editing safely

- Never overwrite the save that was loaded; **Save as** writes a new
  `SAVEn.GAM` (the game only loads `SAVE1`–`SAVE9`).
- An edit must leave the save consistent (e.g. terrain edits keep
  continent/landmass IDs consistent; see STORY-017 and STORY-029, and
  STORY-021 for round-trip safety).
- Don't leave test edits in a save someone else is using.

## 10. Testing

- Test behaviour: given a binary / a save, when decoded or edited, then
  this result.
- A bug fix comes with a test that fails without the fix.
- Build synthetic fixtures in the test for format logic. Keep real-file
  tests few, tagged and skippable.
- Tests must be deterministic: no wall-clock sleeps, no dependence on
  order or on a running dev server.

## 11. Running the app

- Start the dev server with `bash scripts/dev_server.sh` (port 4000). It
  sets `MIRROR_MOM_PATH` and the `MIRROR_*_OFFSET` save-block offsets.
- **You own the server you start: stop it when you're done.** A server left
  over from an earlier session is a mistake; stop it rather than running a
  second one (`lsof -iTCP:4000 -sTCP:LISTEN`).
- zsh doesn't word-split `$VARS`, so `env $VARS mix test` silently passes
  one argument. Use `scripts/test_game.sh`.

## 12. Documentation and tickets

Docs are maintained product surface.

- `docs/` is the project's state: `epics/` (large bodies of work),
  `stories/` (units of work, indexed in `stories/README.md`),
  `backlog.md` (unsorted ideas), `notes/` (dated session notes),
  `reference/` (format write-ups and primary sources).
- **Ideas that come up mid-task become tickets**: a story in
  `docs/stories/`, linked from its epic and from the stories index, or a
  backlog line if it's small.
- When a story is done, mark it done, record the outcome in the story, and
  update the epic and index.
- At the end of a working session, update the handoff note in
  `docs/notes/` so the next person knows where things stand.
- `README.md` describes what Mirror does *now*. Remove stale instructions
  rather than appending corrections beneath them.
- A TODO says what remains and why.

## 13. Review your own work

Before calling something done: read your whole diff, remove accidental
changes, check error paths and edge cases, check that docs match the
code, check for anything from a game file, and run §1's checks.

## 14. Reporting

Be concise and concrete. When you finish, report what changed, the
important decisions, the checks you ran and their results, and anything
left unresolved. Never claim a test passed, a build worked or a bug is
fixed without having seen it.

When several solutions are valid, prefer the one that is easier to
understand, easier to test, easier to change, and harder to misuse. Keep
the plumbing boring; the game's formats are weird enough.
