# Setting up on Windows

What was done, and what was found, getting Mirror, mompy, evi/gama and DOSBox
Staging working on a Windows 11 machine (2026-10-15). Everything below was run
for real unless it says "not tried". The game copy used was the **Steam**
release, not GOG 1.31.

## Summary

| Part | State |
| --- | --- |
| Mirror: `mix setup`, tests, dev server, map drawing | Works (Steam game files). 5 test failures on Windows, fixed in PR #147. |
| mompy | `--version` and its 312 tests pass. With the Steam game loaded in DOSBox 0.83.0, `mompy doctor` says READY and `poke city` changed a city's population (confirmed in game). |
| evi / gama | Install and tests pass. `gama status` runs against the vault but prints nothing: the `checkpoints` table is empty. |
| DOSBox Staging 0.83.0 (released) | Web API works on Windows. |
| Research fork build, Windows `live_session`, rest of the Steam test | Not done (see "Left to do"). |

## Tools installed (per user, with mise)

The machine already had [mise](https://mise.jdx.dev/), Git, GitHub CLI, Node 24
(older Elixir 1.16.3 / OTP 26 and Python 3.11 were the mise defaults). Added,
side by side, without changing any default:

```
mise install erlang@29.1 elixir@1.20.4-otp-29 python@3.14 uv
```

Result: Erlang/OTP 29.1 (erts 17.1), Elixir 1.20.4, Python 3.14.8, uv 0.13.1.
Because the defaults were not changed, run things through `mise exec`:

```powershell
$m = 'erlang@29.1','elixir@1.20.4-otp-29','node@24'
mise exec @m -- mix test --warnings-as-errors
```

Note: mise's Windows Python 3.14 is the **free-threaded** build. gama, evi and
mompy all ran fine on it.

## Git line endings (important)

Windows Git defaults to `core.autocrlf=true`, which checks files out with CRLF.
`mix format` then rewrites files to LF, so every file shows as modified and
`mix format --check-formatted` fails on files that are fine in the repository.
In the Mirror checkout set:

```
git config core.autocrlf input
```

and re-checkout (`git rm -r --cached -q . && git reset --hard -q`, only on a
clean tree) so the working files are LF.

## Mirror

```
mix setup                  # fetched deps (heroicons straight from GitHub), Tailwind 4.1.12 and esbuild 0.25.4 for Windows
mix test --warnings-as-errors
```

* `mix setup` works on Windows with Git on the PATH. No Visual Studio needed.
* **Test result:** 695 passed, 20 skipped with no game path set; 698 passed,
  17 skipped with `MIRROR_MOM_PATH` pointing at the imported files (the
  expected counts with a full set of GOG files and saves are 699 / 16; the
  saves `SAVE1.GAM` etc. were not available here, so a few game-file tests
  still skip).
* **Before the fix** 5 tests failed (690/695). All Windows-specific:
  * `Mirror.SaveFile.write/3` refused to overwrite any existing file because
    `File.stat` returns inode 0 on Windows. This is a real bug, not only a
    test problem. Fixed in
    [#147](https://github.com/ApocryphaCipher/Mirror/pull/147), with branches
    on `:os.type()` / a non-zero inode so macOS and Linux behave as before.
  * Three `SaveManager` tests and one load-box test assumed POSIX paths
    (`Path.expand` returns `c:/...` on Windows).
* Paths with backslashes typed into the Load box work
  (`C:\Users\kevin\mirror-test\TEMPLATE.GAM` loaded).

### Environment variables

PowerShell:

```powershell
$env:MIRROR_MOM_PATH = "$env:USERPROFILE\.mirror\game"
$env:MIRROR_HOME     = "$env:USERPROFILE\.mirror"
mise exec @m -- mix phx.server      # http://localhost:4000/arcanus
```

`MIRROR_HOME` was set explicitly; the importer put the game files in
`C:\Users\kevin\.mirror\game`. The bash scripts in `scripts/` were **not**
tried (Git Bash is installed, so they should run, but they were not tested).

## Steam copy of the game (backlog item "test on a Steam copy")

Install used: `Master of Magic Classic\Master of Magic Official Release` in a
Steam library. It contains the DOS game plus a `DOSBOX` folder (DOSBox 0.74-2),
a `Launcher` folder, and two configs (`dosboxMOM.conf`, `dosboxMOM_single.conf`).
It has **no saved games**, only `TEMPLATE.GAM`.

```
mix mirror.import_game "<install folder>"
```

| File | Result |
| --- | --- |
| TERRAIN, FONTS, UNITS1, UNITS2, SPELLDAT | copied, matches the GOG release |
| MAPBACK, ITEMPOW, ITEMDATA | copied, **not the GOG release's version** ("may still work") |

Checked: the dev server started, `TEMPLATE.GAM` (copied out of the game
folder) loaded from `/arcanus`, and the map drew correctly with terrain art
from the Steam files. **Not checked at that point:** the three differing files in use
(item data and powers, map background), other tabs, editing and saving, real
saves. **Update (Kevin, 2026-10-16):** the three differing files (`MAPBACK.LBX`,
`ITEMPOW.LBX`, `ITEMDATA.LBX`) were tested under Windows with the Steam copy
and work as expected, and the edits listed under "Confirmed by Kevin" below
worked too.

## Python tools

* **mompy** (Python 3.12+, standard library only): run from the checkout,
  `python -m mompy --version` (0.1.0). Its 312 unit tests pass (about 5 min).
  `python -I -m mompy` does **not** work (isolated mode drops the current
  folder from the import path); run it without `-I`.
* **gama / evi** (Python 3.14+): `uv sync` in each; `uv run pytest` gives 10
  and 5 passed.
* **Vault:** `EVI_HOME` (or `--home`) pointing at the `mom-evi-vault` checkout.
  `gama status` exits 0 but prints nothing, because the vault's `checkpoints`
  table has 0 rows (the vault has about 4,000 blobs). Nothing was written to
  the vault. Whether it needs `gama rebuild` was not tried.

## DOSBox Staging 0.83.0 (released build)

Downloaded `dosbox-staging-windows-x64-v0.83.0.zip` (38 MB, no installer) and
unzipped it. A copy of the game folder was mounted so nothing was written to
the Steam install:

```powershell
dosbox.exe --set webserver_enabled=true -c "mount c <copy of game>" -c c: -c WIZARDS.EXE
```

`python -m mompy doctor` then reported:

```
[ok  ] DOSBox  0.83.0 (7b400)
[ok  ] Memory  read 16 MiB
[FAIL] Game    no wizard table found: load a saved game first
```

So the web API works on Windows with the released build and memory reads
work. The game step needs a game loaded with all five wizards; Steam's copy
has none, so the first run said NOT READY. With a game loaded (see below) it says READY.

## Left to do

* Research fork (`ApocryphaCipher/dosbox-staging`, branch `apocrypha/research`):
  not built. Needs CMake, vcpkg and Visual Studio 2022 C++ tools. The
  `dosbox-staging` checkout downloaded is on `main`.
* A PowerShell equivalent of `scripts/live_session.sh` (it is macOS-only).
* Try `scripts/dev_server.sh` and `scripts/test_game.sh` under Git Bash.
* `gama rebuild` / why the vault's `checkpoints` table is empty.

## Round trip on the Steam copy (tested)

1. DOSBox Staging 0.83.0 with the **Steam game folder mounted directly** and
   the web API on (the mount goes in a small config file, because quoting a
   path with spaces on the command line broke):

   ```
   [autoexec]
   mount c "E:\SteamLibrary\...\Master of Magic Official Release"
   c:
   ```

   ```powershell
   dosbox.exe --noprimaryconf -conf steam-mount.conf --set webserver_enabled=true
   ```

   Start the game by hand from `C:\>`. Saves then land in the Steam folder.
2. In-game, with a map loaded: `mompy doctor` gave **READY** (wizard table at
   0x3239a, 28 cities, 42 units, writes accepted). `mompy where pointer`
   named the city under the mouse; `mompy poke city <name> population 25`
   changed it (4 -> 25). `poke city` takes a name, not `pointer`.
3. Saved from the game, loaded in **Mirror** from `~/.mirror/game`, edited
   the map and saved as `SAVE3.GAM`. Copied `SAVE3.GAM` into the Steam folder
   and loaded it in the game: it loads and **the map edits are in place**.

So the Steam copy works for the live API (mompy) and for a Mirror save round
trip. Still unchecked on Steam: the three LBX files that differ from GOG in
every screen that uses them.
