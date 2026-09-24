# 2026-09-24: What the live-RAM sessions proved, and what's next

Two play sessions (2026-09-23) read and wrote the running game's memory
through the DOSBox fork ([live-ram-map.md](../reference/live-ram-map.md)).
This note sorts the results by what Mirror can build on, and lists the
cheap experiments that would settle what's left.

## Why RAM findings apply to save files

For the blocks that matter, the game keeps the save's bytes unchanged in
RAM: wizard records, terrain, units and minerals were **byte-identical**
to `SAVE4.GAM` written at the same moment, and the city block matched
chunk for chunk. All offsets below are record-relative, so they hold for
the `.GAM` file as they are. Two things are RAM-only and don't transfer:
the battle table and the Surveyor numbers (computed on the fly).

## Per story: ready or not

| Story | Verdict | Evidence now in hand | Still open |
| --- | --- | --- | --- |
| [STORY-008](../stories/STORY-008-node-auras.md) node auras | **Ready** | Owner `+3` flips −1 → 0 on meld; `+4` power = aura tile count; the `+5`/`+25` aura lists name exactly the tiles that sparkled; no sparkles before the meld. **Sparkles are in the owner's colour, not the realm's:** Freya's (yellow) sparkles on a Sorcery (blue) node | Animation frames and timing |
| [STORY-011](../stories/STORY-011-sites-towers-lairs.md) sites | **Ready** for intact sites | Encounter kinds named by Surveyor: 3 (Sorcery node), 6 (Ancient temple), 7 (Keep); matched by position on screen: 4 (Cave) and two more temples; 5 (Dungeon) and 10 (Fallen temple) only from the table; x/y/plane checked on every one of these; intact `+3`; **guard count nibbles settled** (low = left, high = starting); rewards | `+15` explored-by bits; what a *cleared* lair looks like on the map |
| [STORY-012](../stories/STORY-012-units-with-banner-plaques.md) units | **Ready** | x, y, plane, owner `+3`, type `+5` checked; all five banner colours checked (wizard `+0x16`); type → name via the game's own table; **dead units stay in the table with plane and owner `0xff`** (skip them) | Whether the *save* compacts dead units; neutral plaque colour; figure art per type (raw screenshots can check) |
| [STORY-013](../stories/STORY-013-roads-minerals-corruption.md) specials | **Ready** | Minerals **4 Gold, 5 Gems, 7 Adamantium, 64 Wild game, 128 Nightshade** checked on screen; Myrror is the minerals map's second plane; Nightshade is not a city flag (compute it from the catchment) | 1, 2, 3, 6, 8, 9 (kazzmir only); corruption bit |
| [STORY-033](../stories/STORY-033-cities-town-frames-rival-flags.md) cities | **Needs a rule change** | Size `+19` drives the title (Hamlet 1, Village 2), but **the map sprite followed population** (5,000 drew the Village sprite while `+19` was still 1); rival banner colours all checked | Draw the frame from population or from `+19`? Town+ frames; flag pixel shades |
| [STORY-034](../stories/STORY-034-surveyor.md) Surveyor | **Evidence yes, formula no** | 11 hovered tiles, 5 full City Resources readouts (Hamburg, Capua, Cremona, Sidon, Bloodrock), each with its catchment; proven computed, not stored | The formula (kazzmir's code, or derive it from the five cases) |

## Record fields proven (beyond the stories)

- **Wizard:** research left `+0x25a` and spell `+0x262` (10 = Earth
  Lore); skill left this turn `+0x54` (drops by each spell's cost, paid
  when the spell is chosen); nominal skill `+0x56`; power base `+0x26`;
  fame `+0x24`; skill share `+0x2c`.
- **City:** population = `+20` × 1000 + `+24` × 10 (proven by a write);
  item in production `+28` and building flags at `+31+n` share ids
  (2 Housing, 26 Marketplace, 29 Granary, 35 City Walls); stored
  production `+94`; production and gold per turn `+93`, `+96`; race `+14`
  (0 Barbarian, 5 Gnoll, 11 Nomad); every starting capital has ids 3, 8,
  32; buying costs 4 × cost when nothing is stored.
- **Unit:** moves `+4`/`+8` in half-moves, destination `+9`/`+10`, orders
  `+18` (0 ready, 2 Patrol, 4 Done, 5 going to), enchantment bits
  `+24..+27` (0x200 Resist Elements, 0x800 Stone Skin); *guess:* `+14`
  experience.

## Still guesses (each has a named check)

| Guess | Cheap check |
| --- | --- |
| Encounter `+15` = explored-by bits | Surveyor the cave at Myrror (28, 28), whose flags are `0x01`: "Explored"? |
| A cleared lair disappears from the map | Clear the easy Myrror temple (28, 21): 1 Skeletons + 1 Zombies; screenshot after |
| City `+67..+92` = the 26 city enchantments | Cast any city enchantment on Hamburg and diff |
| Ids 3, 8, 32 = Barracks, Smithy, Builder's Hall | Hover the buildings in Hamburg's city screen |
| What updates city size `+19` | Watch Hamburg across turns (it went 1 → 2 somewhere after 5,700) |
| Unit `+14` = experience | Open a garrison unit's info: "N ep" |
| Wizard `+0x25e` = casting skill points | Compare with casting skill as it rises |
| The save keeps dead units in place | Save after a battle and read the units block |
| Race 2 = Dark Elf | Open Bloodrock's city screen |

## Suggested order

1. **STORY-012 units** and **STORY-013 specials**: both fully backed now,
   and the biggest visible gain. Units need only the dead-unit check.
2. **STORY-008 node auras**: small, and the colour question is answered.
3. **STORY-011 sites**, drawing intact sites first; clear one lair in the
   next session to learn the cleared look.
4. **STORY-033**, after one session watching Hamburg's size and sprite
   with raw screenshots (the new screenshot endpoint makes this cheap).
5. **STORY-034** last: it needs a formula, not more evidence.

Next play session: the nine checks above, each one checkpoint, with a
dump and a raw screenshot. Most take a single click in the game.
