# Live RAM: reading the running game through DOSBox

This is a tool for agents, not a Mirror feature. Mirror reads save files and
never talks to DOSBox. The DOSBox Staging fork below lets an agent read the
game's memory while Kevin plays, so save-format guesses can be checked
against the running game turn by turn.

First session: 2026-09-23. Dumps and the matching save are in
`~/.mirror/dev/DOSbox/ram-dumps-2026-09-23/` (list at the end).

## The tool

- **Source:** `~/repo/c++/dosbox-staging`, a fork of DOSBox Staging
  (`ApocryphaCipher/dosbox-staging`, GPL). Upstream already has an HTTP
  API (`src/webserver/`); the fork's branch `webserver-write-guard` only
  adds `webserver_allow_writes` (off by default: memory writes,
  allocate/free and shutdown return 403) and refuses non-loopback bind
  addresses.
- **Build:**
  `VCPKG_ROOT=$HOME/vcpkg cmake --preset=debug-macos && cmake --build --preset=debug-macos`.
  The binary is `build/debug-macos/Debug/dosbox`. If configure says
  "No CMAKE_C_COMPILER could be found", Xcode needs
  `sudo xcodebuild -runFirstLaunch` (Kevin runs it; it needs a password).
- **Launch** (Kevin does this; it opens a window, and DOSBox will not run
  headless):

  ```bash
  cd ~/DOS && ~/repo/c++/dosbox-staging/build/debug-macos/Debug/dosbox --set webserver_enabled=true .
  ```

  That mounts `~/DOS` as `C:`; then `cd MAGIC` and `magic`.
- **Read** (the API serves requests on the emulation thread, so reads are
  consistent within a request):

  ```bash
  curl -s http://127.0.0.1:8086/api/v1/memory/0/16777216 -o dump.bin   # all 16 MB
  curl -s http://127.0.0.1:8086/api/v1/memory/0x328ba/1224 -o wiz0.bin   # one range
  curl -s http://127.0.0.1:8086/api/v1/cpu/state                         # registers
  ```

  Writes stay off. Don't ask for them unless Kevin wants to poke the game.

## How to work with it

The game is turn-based, so Kevin stops at a **checkpoint** (a screen that
waits for input) and says so; the agent dumps; Kevin does one thing; the
agent dumps again and diffs. Useful checkpoints: right after loading a
save, the start of a turn on the map, one known action (pick research, buy
something), and right after saving to a slot.

**Matching a save against RAM** found almost every block in one pass: cut
the `.GAM` into 64-byte chunks, find each chunk in the dump, and group runs
where `ram_address − save_offset` stays constant. Skip chunks with ≤ 2
distinct byte values (they match everywhere).

## Findings (Freya game started from SAVE3 "God mode", 2026-09-23)

The run started from SAVE3 and was saved to slot 4 ("Freya - RAM Dump",
backed up with the dumps). **Checked** means byte-for-byte identical to
the save written at the same moment, or matching a value on screen.

### Where save blocks live in RAM

| Save block | Save offset | RAM address | Checked |
| --- | --- | --- | --- |
| Wizard records, 5 × `0x4c8` | `0x0009e8` | `0x0328ba` | checked: 6120/6120 bytes |
| Terrain, 2 × 2400 × u16 | `0x002698` | `0x072630` | checked: 9600/9600 |
| Cities (Zwolle's name) | `0x008aac` | `0x06f980` | checked: whole block runs at save + `0x66ed4` |
| Units, 1009 × 32 | `0x00b734` | `0x07e060` | checked: 32288/32288 |
| Minerals, 2 × 2400 | `0x013554` | `0x0760b0` | checked: 4800/4800 |
| Terrain flags | `0x01cbb8` | save + `0x5a7e8` | checked: the non-zero runs match |
| `0x015c80..0x01c040` | | save + `0x174cdc`, about `0x18a95c` | checked: runs match; *guess:* movement-cost maps |

- The **wizard records** are the only block inside the game's data segment
  (`0x289f0`, i.e. segment `0x289f`). The rest are separate far-heap
  allocations: landmass, nodes/lairs and terrain flags each have their own
  delta, 0x30 apart where they sit back to back. Some blocks
  (`0x6080..0x6bc0`, nodes and fortresses) also have a second copy in RAM.
- **Heroes** (save `0x0000..0x09e8`) are in RAM around `0x07d5b0`, but the
  delta grows by 0x2c–0x3c per record, so the RAM layout differs from the
  save's. Not decoded.
- One block sits **above 1 MB** (extended memory), so always dump the whole
  16 MB, not just conventional memory.

**The addresses are not guaranteed to be stable.** They held across four
turns in one session and across one relaunch (the city block, at least), but the far-heap blocks are allocated at start-up and
could move with a different DOSBox memory config or even a fresh launch.
Re-find them each session: search for the wizard name ("Freya") at record
`+0x01`, or re-run the save match. Don't hard-code them.

**Use SS, not DS, for the data segment.** DS changed from `0x289f` to
`0x48c4` between turns as the game switched code overlays; SS stayed
`0x289f`.

### New wizard record fields

Offsets are from the start of a wizard record (see
[wizard-record-and-exploration.md](wizard-record-and-exploration.md)).
Evidence: all five wizards across four dumps.

| Offset | Field | Evidence |
| --- | --- | --- |
| `+0x25a` | research points left (u16) | checked: 250 when Earth Lore was picked (the book's cost), then 243 next turn (7/turn, the book's "36 turns"); the AI wizards also count down |
| `+0x262` | spell being researched (u16) | checked: set to 10 when Kevin picked Earth Lore, set for all AI wizards at the same moment, unchanged next turn. *guess:* 10 is Earth Lore's id in the spell list |
| `+0x25e` | *guess:* casting skill points (u16) | only rises: Freya 2500 → 2506 → 2512, AIs 245–565. Confirm against the Magic screen's casting skill |
| `+0x130..+0x14f` | unknown, 16 × u16 | filled with 10–15 for every wizard on the first turn change, then roughly doubled the next; a running total of something |

**Gold and mana stuck at 30000.** At the research screen of turn 2, Freya
had 30006 gold (+6 income) and 30005 mana (+5), both matching the incomes
shown on screen. By the map they were 30000 again, and stayed there.
*guess:* the game caps gold and mana at 30000. Check by spending some
first and watching income apply normally.

## Writes

Start DOSBox with `--set webserver_allow_writes=true` as well. Write with
a compare-and-swap so a stale read can't clobber anything: `If-Match`
carries the base64 of the bytes you expect, and the API answers 412
(and changes nothing) if they differ.

```bash
# set a u16 to 50 only if it is currently 0
curl -X PUT -H 'Content-Type: application/octet-stream' -H 'If-Match: "AAA="' \
     --data-binary $'\x32\x00' http://127.0.0.1:8086/api/v1/memory/$((0x6f980+24))
```

Then have Kevin open the screen that shows the value. A write the game
displays is the strongest check we have: it proves the field *drives* the
game, not just that it matches.

**City population, checked 2026-09-23.** After a fresh load of SAVE3 the
starting city (renamed Hamburg) was still at RAM `0x6f980`, the same
address as in the earlier launch. Its record held `+20` = 4 and `+24` = 0,
and the city screen showed 4,000. Writing 50 to `+24` made the city screen
show **Population: 4,500 (+120)**. So:

- shown population = `+20` × 1000 + `+24` × 10 (`+24` is u16 tens,
  0–99; *guess:* the game carries into `+20` at 100);
- growth (+120) did not change, so it is computed, not stored beside the
  population.

## The dumps

In `~/.mirror/dev/DOSbox/ram-dumps-2026-09-23/`, each a full 16 MB:

| File | Moment |
| --- | --- |
| `cp0_name_city.bin` | after loading SAVE3, at "Name Starting City" (turn 1) |
| `cp1_research_pick.bin` | turn 2, "Choose a new spell to research" |
| `cp2_after_pick.bin` | turn 2, back on the map after picking Earth Lore |
| `cp3_turn3.bin` | turn 3, map |
| `cp4_saved.bin` | turn 3, map, right after saving to slot 4 |
| `SAVE4.GAM` | the save written just before `cp4` |
