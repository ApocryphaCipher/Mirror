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
  API (`src/webserver/`); the fork's branch `webserver-write-guard` adds
  `webserver_allow_writes` (off by default: memory writes, allocate/free
  and shutdown return 403), refuses non-loopback bind addresses, and adds
  a **screenshot endpoint** (below).
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
- **Screenshot** of the next frame, taken on the emulation thread like
  the screenshot hotkeys:

  ```bash
  curl -s -X POST http://127.0.0.1:8086/api/v1/capture/screenshot                 # raw: the game's own frame (320x200 in-game)
  curl -s -X POST "http://127.0.0.1:8086/api/v1/capture/screenshot?type=rendered" # what Kevin sees (CRT shader)
  curl -s -X POST "http://127.0.0.1:8086/api/v1/capture/screenshot?inline=1" -o shot.png
  ```

  It answers with `{"path": ...}` once the PNG is complete (files land in
  `~/Library/Preferences/DOSBox/capture/`), or with the PNG itself for
  `inline=1`. Types: `raw` (default), `upscaled`, `rendered`. **At each
  checkpoint take a raw screenshot together with the dump** and keep it
  beside the dump, so the bytes and the screen are from the same moment.
  Raw frames keep the exact palette colours, for sprite and flag checks.

- **Keep and analyse** with [Evi](https://github.com/ApocryphaCipher/evi)
  and [gama](https://github.com/ApocryphaCipher/gama): with
  `EVI_HOME=~/repo/mom-evi-vault`, `uv run gama ingest <dumps>
  --collection <name>` adds dumps to the private Evi vault (stored as
  shared pages, with provenance) and decodes them into SQLite;
  `uv run gama sql "..."` queries them. Screenshots and other evidence go
  in with `evi add`, and findings become `evi claim`s linked to them.

- **One call per checkpoint:** `EVI_HOME=~/repo/mom-evi-vault uv run gama
  checkpoint "bought granary"` (in `~/repo/python/gama`) saves all 16 MB of
  memory, a raw screenshot and the CPU registers into the vault as one
  checkpoint and decodes it. Use it for every checkpoint.
- **DOS file-call log:** start DOSBox with
  `--set webserver_file_log=files.jsonl` to log every file open, read,
  write and seek with the memory address used. After saving the game,
  `uv run gama filemap files.jsonl --file 'SAVE*.GAM' --op write` lists
  every save block with the RAM address it was written from. That is how
  to place the blocks we haven't found (heroes, explored map, the block
  above 1 MB) without guessing.

- **Memory signatures:** start DOSBox with
  `--set webserver_signature_dir=$HOME/repo/python/gama/signatures/mom` and
  the fork watches memory as you play: every city's population, size,
  buildings and enchantments, node owners, cleared lairs, the unit count,
  the minerals map, and Freya's fame, research, summoning circle and
  combat skill. Each change goes to `hits.jsonl` there with old and new
  values and a window of the memory around it; some also take a
  screenshot. A signature can pause the game so a `gama checkpoint`
  catches the moment. See gama's README and `signatures/mom/`.

## How to work with it

The game is turn-based, so Kevin stops at a **checkpoint** (a screen that
waits for input) and says so; the agent dumps (and screenshots) at once,
before anything else; Kevin does one thing; the
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

**Encounter zones (lairs, keeps, node guardians), checked 2026-09-23**
(`cp25`): the 102 × 24 table sits at RAM `0x086660` (save `0x006628` +
`0x80038`); all 102 records parse. Kevin hovered a Keep on Myrror in
Surveyor ("Keep / Unexplored"): record 46 is at (26, 25, plane 1),
kind 7 (Abandoned keep), intact 1, explored-by flags 0, guards Behemoth
(188) count `0x22` and Cockatrices (181) count `0x33`, i.e. 2 and 3 with
equal nibbles, as in SAVE1's intact sites.

**Nightshade is not stored in the city record** (*guess*, `cp32`,
2026-09-23). Of the 27 cities (both planes), only the neutral **Steyr**
(47, 16) has Nightshade in its catchment (the 5 × 5 square minus
corners; the tile at (46, 16)). No city-record byte equals each city's
Nightshade count, and the bytes where Steyr differs from every other
city are ordinary stats (x `+15`, population `+20` = 8, production
`+93` = 13, gold `+96` = 9, and `+102` = 100, unknown), which it gets
from being the largest. So *guess:* the game counts Nightshade from the
minerals plane when it needs it, and Mirror should too. Only one
Nightshade city was available, so this is not proof. The game agrees
on screen: Steyr's city screen (`cp33`) shows an **empty Enchantments
box**.

The same screen checks three city fields: "Village of Steyr" with size
`+19` = 2; "Gnoll" with race `+14` = 5 (and Hamburg, "Barbarian", has
race 0; Capua, "Nomad", race 11, `cp37`; Bloodrock, a Dark Elf city
by its sprites and Kevin's reading, race 2, `cp40`); and a granary silo in the picture with building id 29 flagged.
Hamburg's size byte, still 1 at 5,700 people, was **2** by `cp33`, so it
does update, just not at the first end of turn after crossing 5,000;
what triggers it is still open.

All five starting capitals, Hamburg, Capua (`cp37`), Cremona (`cp38`),
Sidon (`cp39`) and Bloodrock (`cp40`), have exactly building ids 3, 8 and
32 built, so that is the starting set; *guess:*
Barracks, Smithy, Builder's Hall.

Bytes **`+67..+92`** are zero in every city: 26 bytes, the number of
city enchantments in MoM. **Checked** as the city enchantment block: the
enchantment Kevin cast on his capital set slot 14 to 1 (ReMoM: slot `0x0E`
is `Natures_Eye`; value = player index + 1), see
[save-to-ram-map.md](save-to-ram-map.md).

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
| `+96` | gold per turn (u8) | checked: 8, and the screen showed 8 coins; 8 → 12 when the Marketplace (+50% gold) was built |
| `+31+n` | built flag for building id *n* (1 built, `0xff` not) | checked three times: Granary (id 29) set `+60`, Wall of Stone set `+66` (City Walls, id 35), and a bought Marketplace (id 26) set `+57` the next turn (`cp19`), predicted in advance |
| `+30` | unknown | 3 → 4, then unchanged, later 5 → 6 across turns; unchanged by buying or switching production; not a plain turn counter |
| `+19` | size | still 1 (Hamlet) after the turn ended at 5,080, so the end-of-turn guess above is **wrong**; the city title still said "Hamlet" |

So production ids and building ids are the same numbering (2 = Housing,
29 = Granary, 35 = City Walls). *Guess:* the other built flags in
Hamburg, `+34`, `+39`, `+63` (ids 3, 8, 32), are the starting Barracks,
Smithy and Builder's Hall; check against the city screen's building
list.

Buying with nothing stored costs **4 × the building's cost** and fills
`+94` to the full cost, checked twice: Granary 160 gold for cost 40
(`cp5` → `cp6`), Marketplace 400 gold for cost 100 (`cp15` → `cp16`,
`+94` = 100). The price with some production already stored is not yet
checked.

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
- **Arrival** (`cp12`): the Sprites reached (39, 22); `+9`/`+10` cleared
  to (0, 0) and `+18` went 5 → 0, so 5 = going to (checked by arrival).
  **Wait stores nothing**: the Swordsmen's `+18` stayed 4 after Wait.
- **`+14`**, *guess:* experience. It rose 1 → 2 → 3 over two turns on
  both garrison units and stayed 0 on the (summoned) Sprites; the text
  buffer held "Regular (1 ep)" earlier. Check against a unit's ep.
- **Unit enchantments are a bit field at `+24..+27`** (u32), checked
  (`cp14` → `cp15`): Stone Skin cast on the Magic Spirit (slot 59; Kevin
  saw the green aura) changed only `+25`, `0x00` → `0x08`, i.e. bit
  **`0x800` = Stone Skin**. Then Resist Elements added **`0x200`** on the
  Magic Spirit (`0x800` → `0xa00`, `cp17`) and on the fourth Sprites
  (slot 51, `0` → `0x200`, `cp18`). Both match kazzmir's enchantment
  order, so *guess:* the remaining bits follow it too.
- **Spell cost is paid when the spell is chosen**, checked twice: mana
  and skill left were unchanged between the target list and the cast for
  Stone Skin (`cp14`/`cp15`) and Resist Elements (`cp16`/`cp17`), and
  had already dropped by 9 at the Resist Elements target list. A second
  Resist Elements took skill left from 9 to 0 and was allowed.
- The unit list shown for targeting (and "Freya Units") is in unit-table
  slot order: its fourth Sprites row was slot 51.
- **`+8` is moves left, `+4` moves per turn**, in half-moves. `+8`
  checked: after moving one tile the Sprites had 2 and the screen said
  "Moves: 1". Earlier evidence from the Sprites (`+4` = 4, "Moves: 2" on screen; `+8` 4 → 0
  after an accidental two-tile move) and the garrison (`+4` = `+8` = 2,
  one move).
- The route is not in the unit record. *guess:* the data segment holds a
  step buffer the map draws from: three 120-entry arrays 0x78 apart at
  `ds+0xc5f0` (per-step cost, 2 each), `ds+0xc668` (y) and `ds+0xc6e0`
  (x); for the eastward path the first three entries were (37, 22),
  (38, 22), (39, 22).

**Moving a stack by writing `+0`/`+1`, 2026-09-23.** With writes on,
all nine units of Kevin's stack (slots 42, 49–54, 59, 60) were moved from
(35, 19) to (41, 10), next to the Sorcery node at (42, 10) (terrain 168),
with one compare-and-swap per unit. Before writing, the target was checked
to be free of units, cities and encounter sites. (The city check first
used a wrong table start; re-run with the right one, **city 0 at RAM
`0x06f980`**, it still found no city there.) The stack **vanished
from the map** until the turn ended, then showed at (41, 10) with full
moves, destination cleared and orders 0; the game did not continue the
go-to into the node. *guess:* the map draws units from a visibility or
draw cache rebuilt at end of turn, and a go-to stops rather than start a
fight. Dumps `cp26` (before) and `cp27` (next turn).

**Combat, first look, 2026-09-23** (`cp28`, Kevin's stack vs the
Sorcery node at (42, 10), start of his first combat turn):

- When the battle starts, the game **creates the node's guardians as
  overland units**: slots 74–81 held 8 Phantom Warriors (type 192) at
  (42, 10), owner 5 (neutral). Encounter record 19 still said 8 guards
  (`0x88`), intact.
- A **battle unit table**: 17 records, `0x6e` (110) bytes apart, first
  the attacker's 9 units, then the 8 guardians. Each record holds the
  overland unit slot as a u16; for record *j* it is at RAM
  `0x05bde0 + j × 0x6e`. *guess:* the bytes before it
  are the unit's combat stats (identical for every Sprites record,
  different for the Magic Spirit and the Phantom Warriors), and the u16
  pairs after it are battlefield positions. Record start and field layout
  are not worked out yet.
- **Mid-fight diff** (`cp28` → `cp29`; Kevin's Sprites each shot once,
  he moved one Sprites and the Magic Spirit, killed some Phantom Warriors
  and cast Earth to Mud). Offsets are from the overland-slot u16:
  - `-0x2d`: 4 → 3 on all eight Sprites. *guess:* ranged shots left.
  - `+0x14` / `+0x16`: changed by one step only for the two units Kevin
    moved (and for moving guardians). *guess:* battlefield x, y.
  - `+0x18` / `+0x1a`: changed on units that only shot, too. *guess:*
    target or facing point.
  - `-0x23`: 6 → 0 on three Phantom Warriors (slots 74, 76, 80), with
    `+0x4` = 4 and `+0x6` set. *guess:* figures left (Phantom Warriors
    have 6), so 0 = dead.
  - `-0x29`: 2 → 0 on the guardians that moved. *guess:* moves left.
  - Overland mana dropped 6 (Earth to Mud); overland skill left did not
    move, so combat keeps its own skill counter. The encounter record
    still said 8 guards: it is updated only after the battle.
- **After the victory** (`cp30`, on the map, "Inside you find 150 mana
  crystals", "You have gained 1 fame"):
  - mana 29805 → 29955 (+150, the encounter's `+12` reward, which stays
    in the record); fame (wizard `+0x24`) 10 → 11: **fame checked**.
  - The 8 guardian units (slots 74–81) got plane and owner `0xff`: dead
    units are marked in place; the unit count stayed 82.
  - Encounter 19: intact `+3` 1 → 0; guard count `0x88` → `0x80`, which
    **settles the nibbles: low = guards left, high = starting count**;
    flags `+15` `0x02` → `0x06` (one explored-by bit added; which wizard
    each bit is stays open).
  - The node itself (record 7 of the node table, which has two copies in
    RAM at `0x085fe0` and `0x087010`) still had owner `0xff`: beating the
    guardians does not take the node; melding does.
- **The meld** (`cp31`, a turn later, sparkles on screen): node record 7
  owner `+3` `0xff` → 0 in the copy at **`0x085fe0`** (the live table);
  the copy at `0x087010` did not change (*guess:* a stale copy). Its
  aura lists name 5 tiles, which are the ones that sparkle. The Magic
  Spirit (slot 59, type 154) was marked dead in place (plane and owner
  `0xff`).

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
| `cp12_arrived_wait.bin` | next turn: Sprites arrived at (39, 22), Swordsmen on Wait |
| `cp13_sprites_home.bin` | Sprites moved onto Hamburg's tile |
| `cp14_stoneskin_target.bin` | later: stack of 8 Sprites + Magic Spirit at (36, 20), Stone Skin waiting for a target |
| `cp15_stoneskin_cast.bin` | Stone Skin cast on the Magic Spirit (slot 59) |
| `cp16_before_resist.bin` | Resist Elements chosen, at the target list |
| `cp17_resist_on_spirit.bin` | Resist Elements on the Magic Spirit |
| `cp18_resist_on_sprite.bin` | Resist Elements on the fourth Sprites (slot 51); Hamburg building a Marketplace |
| `cp19_marketplace_built.bin` | next turn: Marketplace built; the stack one step along its path to (42, 10) |
| `cp32_surveyor_nightshade.bin` | Surveyor on the Nightshade swamp at (46, 16) beside Steyr |
| `cp33_steyr_city_screen.bin` | Steyr's city screen (Village, Gnoll, no enchantments) |
| `cp34_cartographer_arcanus.bin` | just after closing the Cartographer (Arcanus); game data identical to `cp35` |
| `cp36_surveyor_capua.bin`, `cp37_capua_city_screen.bin` | Surveyor on Capua, then Capua's city screen (Hamlet, Nomad, no enchantments) |
| `cp38_surveyor_cremona.bin` | Surveyor on Cremona (Merlin's capital) |
| `cp39_surveyor_sidon.bin` | Surveyor on Sidon (Jafar's capital), no specials nearby |
| `cp40_surveyor_bloodrock.bin` | Surveyor on Bloodrock (Tlaloc's capital, Myrror, purple flag) |
| `cp41_surveyor_temple.bin` | Surveyor on a Myrror temple (28, 21), encounter 74, kind 6. Other sites in view also match their records, incl. a cave (28, 28) with flags `0x01` |
| `cp35_cartographer_open.bin` | Cartographer open on Arcanus. The screen is graphics: "Arcanus Plane" is not text, and legend names come from the wizard records |
| `cp26`–`cp31` | Sorcery node in Surveyor; next turn after the teleport; first combat turn at the node; mid-fight; back on the map after winning; node melded (sparkles) |
| `cp20`–`cp25` | Surveyor open, hovering: Hamburg area, gold ore (39, 20), wild game (38, 19), gems (32, 25), Myrror adamantium (28, 25), Myrror Keep (26, 25); screenshots `surveyor-*.webp` beside them |
| `SAVE4.GAM` | the save written just before `cp4` |
