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
| `+0x262` | spell being researched (u16) | checked: set to 10 when Kevin picked Earth Lore, set for all AI wizards at the same moment, and the Magic screen said "Researching: Earth Lore" while it was 10 |
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

Then `+20..+25` was rewritten in one compare-and-swap to 5 and 0
(5,000). The map immediately drew Hamburg with the **next, larger city
sprite**, and the income panel dropped from 6 gold / 2 food to 5 / 1 (one
more thousand to feed). But the stored size byte `+19` **stayed 1**
(Hamlet). So:

- the map sprite (and income) follow population live; 5,000 is the
  first sprite change, as Kevin confirmed on screen;
- `+19` is **not** recomputed at end of turn (checked below); what
  moves it is still open.
- For Mirror, "frame = size − 1" still holds for saves, where `+19` and
  population agree, but it is not how the game decides.

**Production and buildings, checked 2026-09-23** (dumps `cp5`–`cp7`).
Kevin queued a Granary, bought it, cast Wall of Stone on Hamburg, and
ended the turn:

| Offset | Field | Evidence |
| --- | --- | --- |
| `+28` | item in production (u16) | checked: 2 while the screen said "Producing Housing", 29 for Granary, back to 2 when switched and after completion |
| `+94` | production stored so far (u16) | checked: 0 → 40 on buying the Granary (cost 40: "5 Turns" at 9/turn), 40 → 0 when it was built |
| `+93` | production per turn (u8) | checked: 9, and the city screen showed 9 hammers |
| `+96` | gold per turn (u8) | checked: 8, and the screen showed 8 coins |
| `+31+n` | built flag for building id *n* (1 built, `0xff` not) | checked twice: Granary (id 29) set `+60`, Wall of Stone set `+66` (City Walls, id 35) |
| `+30` | unknown | 3 → 4 over one turn, then **unchanged** over the next, and unchanged by buying or switching production; not a turn counter |
| `+19` | size | still 1 (Hamlet) after the turn ended at 5,080, so the end-of-turn guess above is **wrong**; the city title still said "Hamlet" |

So production ids and building ids are the same numbering (2 = Housing,
29 = Granary, 35 = City Walls). *Guess:* the other built flags in
Hamburg, `+34`, `+39`, `+63` (ids 3, 8, 32), are the starting Barracks,
Smithy and Builder's Hall; check against the city screen's building
list.

Buying the Granary cost 160 gold (29840 after), 4 × its cost with nothing
stored. *Guess:* that is the buy-price rule when no production is stored.

**Units, checked 2026-09-23** (`cp7` → `cp8`). Kevin cast Sprites
(10 MP) at Hamburg:

- A new record appeared in unit slot 42 (RAM `0x07e060 + 42 × 32`):
  xy (38, 21) plane 0 (Hamburg's tile), owner 0, type (`+5`) **180**.
- **Unit type names**, checked: the data segment has the unit type table
  at `ds+0x19c`, `0x24` bytes per type, with a u16 pointer (DS offset) to
  the name at `+0`. It names 39 Spearmen, 40 Swordsmen and 180 Sprites,
  matching what Kevin saw on screen.
- The **unit count** is a u16 at RAM `0x034782` (`ds+0xbd92`, the only
  u16 in the data segment that went 42 → 43). It is *not* beside the
  wizard records the way save offset `0x9e2` suggests.
- The two garrison units (slots 0 and 5, types 39 and 40) changed only at
  `+18`, 2 and 4 → 0, when the Sprites took the selection.
- **`+18` is the unit's orders**, checked in `cp11`: Kevin set the
  Spearmen (slot 0) to Patrol and the Swordsmen (slot 5) to Done. So
  **2 = Patrol**, **4 = Done** (Done also set moves left `+8` to 0), and
  0 = ready / awaiting orders (every unit on a selected tile shows 0).
  The Sprites have held **5** the whole time they had a destination;
  *guess:* 5 = going to `+9`/`+10`. (An earlier reading of 5 as Patrol
  was wrong: the Sprites were already on a path when Patrol was clicked.)
- The same Patrol order set the Sprites' `+7` and `+11` from 0 to 1, the
  value the older units already had. Unknown.
- **`+9` / `+10` is the move destination (x, y)**, checked against two
  paths Kevin set (screenshots of the boot markers): (32, 22) with the
  boots running west, then (39, 22) running east. The orders byte stayed 5.
- **Paths run across turns**, checked in `cp11`: after the turn ended the
  Sprites had walked two tiles east, (36, 22) → (38, 22), destination
  still (39, 22), moves left 0.
- **`+8` is moves left, `+4` moves per turn**, both in half-moves:
  *guess* (strengthened by the path and by Done zeroing `+8`) from the Sprites (`+4` = 4, "Moves: 2" on screen; `+8` 4 → 0
  after an accidental two-tile move) and the garrison (`+4` = `+8` = 2,
  one move).
- The route is not in the unit record. *guess:* the data segment holds a
  step buffer the map draws from: three 120-entry arrays 0x78 apart at
  `ds+0xc5f0` (per-step cost, 2 each), `ds+0xc668` (y) and `ds+0xc6e0`
  (x); for the eastward path the first three entries were (37, 22),
  (38, 22), (39, 22).

## The dumps

In `~/.mirror/dev/DOSbox/ram-dumps-2026-09-23/`, each a full 16 MB:

| File | Moment |
| --- | --- |
| `cp0_name_city.bin` | after loading SAVE3, at "Name Starting City" (turn 1) |
| `cp1_research_pick.bin` | turn 2, "Choose a new spell to research" |
| `cp2_after_pick.bin` | turn 2, back on the map after picking Earth Lore |
| `cp3_turn3.bin` | turn 3, map |
| `cp4_saved.bin` | turn 3, map, right after saving to slot 4 |
| `cp5_granary_queued.bin` | second run (SAVE3 reloaded, city renamed Hamburg, pop set to 5,000 by RAM write), Granary queued |
| `cp6_granary_bought.bin` | Granary bought, back on the map |
| `cp7_granary_walls.bin` | next turn: Granary built, Wall of Stone resolved |
| `cp8_sprites.bin` | after casting Sprites, Sprites selected on the map |
| `cp9_sprites_patrol.bin` | Sprites ordered to Patrol |
| `cp10_sprites_path.bin` | Sprites given a path east to (39, 22) |
| `cp11_done_patrol_move.bin` | next turn: Spearmen on Patrol, Swordsmen Done, Sprites two tiles along the path |
| `SAVE4.GAM` | the save written just before `cp4` |
