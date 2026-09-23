# STORY-031 (spike): Download the user's own GOG copy from a script

**Parent:** [EPIC-007](../epics/EPIC-007-packaging-ci-and-repo-hygiene.md)
**Status:** open, spike (time-boxed research, then a go/no-go)
**Size:** small (spike)
**Requested by:** Kevin, 2026-09-23 ("a new user just has to buy the game
on GOG"; automate everything after that)

## Goal

Find out whether setup can be: buy *Master of Magic* on GOG, then run one
command that downloads **the user's own copy** (signed in with their GOG
account), unpacks it, and runs `mix mirror.import_game`.

## Scope

The source is the user's own GOG library, downloaded as them. Mirror needs
nothing else from outside: MOMIME (SourceForge) is no longer a dependency.

## Questions to answer

1. **Getting the installer.** Candidates: `lgogdownloader` (CLI,
   Linux/macOS, logs in to GOG and downloads owned games), `gogdl` (the
   Heroic launcher's downloader), GOG's own API. Which one works headless,
   on macOS and Linux (for Docker), without us handling the user's
   password? (The user logs in through the tool's own flow; our script never
   sees the credentials.)
2. **Unpacking it.** GOG ships Master of Magic as a Windows installer
   (`setup_master_of_magic_*.exe`, Inno Setup) and possibly a macOS `.pkg`.
   Does `innoextract` (Windows installer) or `pkgutil --expand` (macOS)
   yield the LBX files? `mirror.import_game` already accepts the unpacked
   folder, so this step only has to produce one.
3. **Which files and versions.** Confirm the downloaded files hash-match
   `Mirror.GameFiles.manifest/0` (Kevin's copy is the GOG release). Note any
   other GOG build.
4. **Dependencies.** These are external tools, not Hex packages. Is
   "install `lgogdownloader` and `innoextract` with Homebrew/apt" acceptable,
   or should the script only check for them and explain?

## Output

A short write-up in this file: what works, the exact commands, and a
recommendation. If it's a go, a follow-up story for
`scripts/fetch_game.sh` (download → unpack → `mix mirror.import_game`) and
its Docker equivalent.
