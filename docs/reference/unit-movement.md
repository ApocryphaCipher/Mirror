# Unit movement: who may stand on water

Needed by STORY-029's edit checker (a unit on water is only odd if it cannot be there). Written
2026-10-11. The code is `Mirror.SaveFile.UnitMovement`.

## Sources, and how far they are checked

- **kazzmir/master-of-magic**, [`game/magic/units/overworld.go`](https://github.com/kazzmir/master-of-magic/blob/master/game/magic/units/overworld.go)
  (`IsFlying`, `IsSwimmer`, `IsSailing`, `IsLandWalker`) and `units/unit.go` (each unit's `Flying`,
  `Swimming` and `Sailing` flags and its abilities); `load/convert.go` (`getUnitType`: save type id to unit,
  and the unit-enchantment bits). Read 2026-10-11.
- **The saves.** Every unit standing on water (landmass 0, not a polar row, not in a city) in every save
  on this machine (about 30 files) is explained by the rule below. That is *consistent with* the rule, not
  proof: only Lizardmen Spearmen and Swordsmen (120, 121), Magic Spirits (154) and Barbarian Settlers
  (44, aboard a boat or enchanted) were ever on water. No flyer, boat or Water Walking unit has been seen
  on water on the save side yet.
- **Not checked in the game:** every row below. Treat the table as kazzmir's word until a unit of each
  kind has been put on water in the real game.

## The rule (kazzmir)

A unit may be on water **without help** when any of:

1. its type **flies** (`Flying`), or it has the **Flight** enchantment (bit `0x20000`), or Chaos Channels
   demon wings (mutation bit 8, record `+23`);
2. its type **swims** (`Swimming`: lizardmen and a few fantastic units) or it has **Water Walking** (bit `0x100`);
3. its type **sails** (`Sailing`: Trireme, Galley, Warship; water only);
4. it is **non-corporeal** (spirits, wraiths, shadow demons, phantoms).

*Guess:* the **Wind Walking** bit (`0x10000`) also lets a unit cross water. kazzmir stores the bit but
`IsLandWalker` does not read it, so the checker should treat it as fine.

A land unit may also be on water **aboard a transport** in the same stack (a boat, or the Floating Island
unit). That is a property of the stack, not of the unit.

**Cities.** Nothing here says a city may be on water. The game loads one (STORY-019). The cities block has
a `flying_fortress` enchantment slot (`+67 + 8`); what it does to a city on water has not been looked at.
Kevin's "flying city spell" is probably that, not Floating Island: **Floating Island is a *unit***
(type 190, a swimming transport), not a city enchantment.

## Unit record bytes this uses (32 bytes at `0xB734`)

From kazzmir's `UnitData` (`load/load.go`); `+0..+5` and `+18` are already read by `Mirror.SaveFile.Units`.

| Offset | Field |
| --- | --- |
| `+0` `+1` `+2` `+3` | x, y, plane, owner |
| `+4` | max moves |
| `+5` | unit type (0..197) |
| `+6` | hero slot |
| `+8` | moves left |
| `+9` `+10` | **go-to destination x, y** (so a stack with orders carries a target; STORY-019's unit moves will need it) |
| `+12` | level |
| `+14` `+15` | experience (i16) |
| `+17` | damage |
| `+20` `+21` | in tower (i16) |
| `+23` | mutations: 8 = Chaos Channels demon wings (flies), 32 = undead |
| `+24..+27` | unit enchantments, u32 bits: Water Walking `0x100`, Wind Walking `0x10000`, Flight `0x20000`, Invisibility `0x8000` (the full list is in kazzmir's `convert.go`) |
| `+28` `+29` `+30` | road turns, road x, road y |

All of these are kazzmir's reading order, not yet checked against the game except `+0..+5` and `+18`.

## Types that may be on water

Every type not listed is a land unit. Type 131 (Nomad Magicians) is missing from kazzmir's
definitions and is presumed land.

| Type | Unit | How |
| --- | --- | --- |
| 17 | Fang (Hero) | flies |
| 35 | Trireme (All) | swims (and walks), sails (water only); carries units |
| 36 | Galley (All) | swims (and walks), sails (water only); carries units |
| 38 | Warship (All) | swims (and walks), sails (water only); carries units |
| 55 | Manticores (Beastmen) | flies |
| 65 | Nightmares (DarkElf) | flies |
| 66 | Spearmen (Draconian) | flies |
| 67 | Swordsmen (Draconian) | flies |
| 68 | Halberdiers (Draconian) | flies |
| 69 | Bowmen (Draconian) | flies |
| 70 | Shaman (Draconian) | flies |
| 71 | Magicians (Draconian) | flies |
| 73 | Settlers (Draconian) | flies |
| 74 | Doom Drake (Draconian) | flies |
| 75 | Air Ship (Draconian) | flies |
| 103 | Pegasai (HighElf) | flies |
| 120 | Spearmen (Lizard) | swims (and walks) |
| 121 | Swordsmen (Lizard) | swims (and walks) |
| 122 | Halberdiers (Lizard) | swims (and walks) |
| 123 | Javelineers (Lizard) | swims (and walks) |
| 124 | Shamans (Lizard) | swims (and walks) |
| 125 | Settlers (Lizard) | swims (and walks) |
| 126 | Dragon Turtle (Lizard) | swims (and walks) |
| 136 | Griffins (Nomad) | flies |
| 146 | Wyvern Riders (Orc) | flies |
| 154 | Magic Spirit (Fantastic) | swims (and walks), non-corporeal |
| 156 | Gargoyles (Fantastic) | flies |
| 159 | Chaos Spawn (Fantastic) | flies |
| 160 | Chimeras (Fantastic) | flies |
| 161 | Doom Bat (Fantastic) | flies |
| 162 | Efreet (Fantastic) | flies |
| 164 | Great Drake (Fantastic) | flies |
| 169 | Demon (Fantastic) | flies |
| 170 | Wraiths (Fantastic) | flies, non-corporeal |
| 171 | Shadow Demons (Fantastic) | flies, non-corporeal |
| 172 | Death Knights (Fantastic) | flies |
| 173 | Demon Lord (Fantastic) | flies |
| 176 | Guardian Spirit (Fantastic) | swims (and walks), non-corporeal |
| 177 | Angel (Fantastic) | flies |
| 178 | Arch Angel (Fantastic) | flies |
| 180 | Sprites (Fantastic) | flies |
| 181 | Cockatrices (Fantastic) | flies |
| 186 | Gorgons (Fantastic) | flies |
| 190 | Floating Island (Fantastic) | swims (and walks); carries units |
| 191 | Phantom Beast (Fantastic) | non-corporeal |
| 192 | Phantom Warriors (Fantastic) | non-corporeal |
| 194 | Air Elemental (Fantastic) | flies |
| 195 | Djinn (Fantastic) | flies; Wind Walking ability |
| 196 | Sky Drake (Fantastic) | flies |
