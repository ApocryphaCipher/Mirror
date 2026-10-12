# STORY-020: Structure detail editors (city / lair / unit)

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** mostly done (2026-10-12). Built and checked in the real game: the city panel (name, population,
buildings, enchantments, race, owner), the lair panel, the node panel and unit editing (level, experience, damage,
owner); see each section below. Left: a unit's type, enchantments and max moves, a hero's owner, and the meaning of
the lair treasure code.
**Progress (2026-10-11), first slice built: the 🏙️ City tool.** Click a city in edit mode: a panel shows its
name, size, race, owner (wizard name and banner), plane and position, garrison count, walls, buildings
(and replaced ones), enchantments with their casters, and road links; name and population can be edited in
the panel, each Apply one undo step (`Structures.edit_city/3`; logic in `MirrorWeb.CityPanel`).

**Real-game check (slot 6, vault checkpoints 90 and 91):** the edited names and population bytes load into the
game's memory unchanged, and the game accepts them (Kevin: Hackerville pop 12 and Zürich pop 20 both
Villages, rebels from the sudden growth, "nothing unusual").
- **Names must be ASCII.** "Zürich" was saved with the Latin-1 byte `fc`, and the game showed "Zrich": the
  font has no "ü". Names are now limited to printable ASCII, 1 to 13 characters.
- **Size class is not recomputed.** The size byte (`+19`) stayed 2 for pop 12 and 20, on load and after an
  End Turn, and across all saves here it overlaps in population (size 1 at pop 1-7, size 2 at 5-12), so it
  is not a function of population. The tool leaves it alone. Setting it, if wanted, is a separate edit.
- **Not checked:** the building names other than 26, 29 and 35 (by order, matching Kevin's cities), the
  25 limit on population, and population above a city's food.
- Race names are checked for Dwarf, Halfling and Lizardman; the panel's race table fixes an earlier
  off-by-one bug in the first draft (a `~w` sigil split "Dark Elf").

**View-mode inspector (2026-10-11).** In View mode, a plain click on a city (one that does not pan) opens the same
panel read-only, with a ✕ to close it; a click on empty ground closes it too. The viewport reports the
click (`assets/js/view_click.mjs` maps the point to a tile through the zoom and pan, Node-tested) and the
server shares the City tool's selection. Checked in the browser on a real save at the fit zoom: Sawtooth
and Hialanth open with their details, no form, close on empty ground and on ✕.

**Buildings (2026-10-11).** In edit mode the panel has a checklist of the 33 buildings a city can have (ids 3 to 35;
1 and 2 are production items): ticked means built or replaced. Applying it is one undo step
(`Structures.edit_city/3`, `buildings:`). The rule is the game's own, from `BUILDDAT.LBX`:
adding a building marks the one it replaces as replaced (Temple replaces Shrine, Bank replaces Marketplace,
Farmers' Market replaces Granary, and so on); removing it brings the replaced one back; a building whose
predecessor is absent is just built. **Prerequisites are a hint, not enforced** (a ⚠ and a tooltip):
real saves break them, since neutral cities have Shrines without a Builders' Hall.
- **Source:** `BUILDDAT.LBX` (Kevin's install) lists each building's name, up to two prerequisites and what it
  replaces, in the save's building order, so its entry index *is* the save id: a second source for every id
  (before, only 26, 29 and 35 were checked in the game). Codes of 100 or more in its prerequisite fields are
  terrain (forest, water, minerals), not buildings.
- **Checked against the saves:** 44 distinct building sets across every save on this machine: every id and every
  "replaced" fits; prerequisites are broken in about 35 places, which is why they stay a hint.
- **Real game (checkpoint 92):** a save with Wizards' Guild, Parthenon and Bank added to Sawtooth and its
  Marketplace marked replaced loaded with the game's memory identical to the file. Per Kevin, each building is
  not checked one by one in the game: the table is documented game data.
- **Not modelled:** race restrictions, terrain needs (a Sawmill wants forest, a Shipwrights' Guild water, a
  Miners' Guild minerals), and what a building does to the city's output (the game derives that).

**Enchantments (2026-10-11).** The panel has a select for each of the 26 city enchantments: none, or the wizard who
cast it (the byte is the caster's index plus one, 0 for none; `Structures.edit_city/3`, `enchantments:`).
The slot order matches kazzmir's `convert.go` exactly (0 to 24; Nightshade is slot 25, from ReMoM) and the
casters' checks in surveyor-formula.md. **Real game (slot 8, vault checkpoint 93, screenshots by Kevin):**
Sawtooth with Flying Fortress, Nature's Eye, Prosperity and Heavenly Light cast by Jafar showed **Flying**,
Nature's Eye, Prosperity and Heavenly Light in blue (Jafar's banner); Hialanth with Pestilence cast by Sss'ra and
Famine cast by Freya showed them in purple and green, their banners. The game's memory matched the file. So an
enchantment's colour follows the caster, and the game names Flying Fortress "Flying" on the city screen.
Effects are the game's to derive; the editor does not check who may cast what, or whether a city has the walls
a Wall of Fire needs.

**Race and owner (2026-10-11).** The panel has a select for each (`Structures.edit_city/3`, `race:` and `owner:`).
Race is the byte at `+14`, 0 to 13. Owner is the byte at `+18`, a wizard record 0 to 4 or 5 for neutral,
and **the units standing in the city that belong to the old owner change hands with it**, so a garrison is
never left inside a city that is not theirs. **A wizard's capital is refused** (`:capital`): a city holding a
fortress record (`0x65F8`) or a wizard's summoning circle, since the wizard record would still point at a city
he no longer owns. On Kevin's played save this refuses exactly the five capitals (Dover, Darkmoor, Braxus,
Myrean and Blackstone, which became Jafar's capital when he moved his fortress). The selects always carry
the city's current value, even an unnamed wizard record, so Apply cannot change it by accident.
**Real game (slot 8, vault checkpoint 94, Kevin at the keyboard):** Hialanth, a neutral Halfling city with 5
units, given to Freya as a Dwarf city, loaded with its banner green, "Dwarf" on its screen, all 5 units
Freya's (the game's memory shows owner 1, race 4 and units owned only by 1 on its tile), and no unrest;
Ashwall, one of Jafar's, made neutral showed no owner and no units. The memory matched the file for both.
**Enchantments are cleared on a change of owner** (Kevin's call, 2026-10-11: which ones would survive is not worked out, and
wiping them is the simple rule); the panel's notice says so. **Not checked:** the capital's race (the wizard record also has a "capital race" byte at `+0x15`).

**Units (2026-10-11).** The **👥 Units** tool and a View-mode click on a tile without a city list the tile's units
(`Units.stack/2`, `UnitTypes.display_name/1`) with owner, level, experience, damage and orders; in edit mode the ticked
ones can be moved (STORY-019 has the rules and the game check). Editing a unit's own fields is not done.

**Lairs and other encounter zones (2026-10-12).** The **🏚️ Lair** tool, and a View-mode click on a site with no city or
units, open a panel for the encounter on the tile: a cave, dungeon, ancient temple, abandoned keep, monster lair, ruins,
fallen temple, a node's guardians or a Tower of Wizardry (`Mirror.SaveFile.Encounters`, `MirrorWeb.LairPanel`,
`Structures.edit_encounter/3`). In edit mode you can change:
- the **Not cleared** state (`+3`);
- each of the **two guard slots**: a unit type (names from `UnitTypes`) and a count 1 to 8, written with both nibbles equal as
  every full slot in the saves is (low nibble = left, high = starting; a half-fought guard shows "started with N" and keeps
  its count if untouched); an empty slot is type 0, count 0 (all 247 empty slots seen);
- **gold and mana** (i16, 0 to 30000; the largest seen are 620 and 330).
A tower is two records (an Arcanus and a Myrror side) with the same guards, and the game clears both together, so a tower is
edited on **both**. Not editable: the **treasure code** (`+14`: it is 0 to 6 in every save, so it is a code, not a spell id,
and what the codes mean is not decoded), the flags, and the items (ids not decoded).
**Real game (slot 5, vault checkpoint 98):** the abandoned keep near Kevin's capital rewritten to 1 Sprite and 2 High Elf Pegasai,
777 gold and 333 mana loaded with the game's memory identical to the file (guard counts `0x11` and `0x22`). **Kevin attacked
it:** the guards were two Pegasai and a Sprite, and the reward screen read "Inside you find 777 gold, 333 mana crystals and a
Create Artifact spell" (checkpoint 98's save; his screenshot). That keep's treasure code was 1.
**The treasure code does not decide the reward (2026-10-12, two more experiments):** keeps next to Blackstone with no gold, mana or items,
one per code 2 to 6 and then a row of six for codes 1 to 6 (one to six Sprites each), cleared by Kevin. The same code gave different
rewards (code 1: a Create Artifact spell once, nothing once; code 5: a Chain Mail once, a Disjunction spell once), so the reward is
**rolled when the site is cleared**: nothing, spells from the realms the wizard has books in plus Arcane (Create Artifact, Summon Hero,
Disjunction, Weakness), a spell book, or an item (the cleared record's item count goes 0 to 1). Gold and mana are the record's own fields.
kazzmir's remake does the same kind of roll, from a budget. What the code itself means is unknown; the panel shows it and does not edit it.

**Nodes (2026-10-12).** The **🔮 Node** tool opens a panel for the magic node on a tile (`Structures.edit_node/3`, `MirrorWeb.NodePanel`):
its type, plane, power, owner (the melder, a wizard record 0 to 4 or none = 0xFF at `+3`), the **warped** (`+0x2E` bit 1) and **Guardian Spirit meld**
(bit 2) flags, and its guardians (the kind 1 to 3 encounter on its tile). Giving a node an owner also **clears its guardians** in the same undo
step, because in every save here an owned node has its guardians cleared (42 of 42) and an unowned one still has them (120 of 120); a
**Clear guardians** button does it alone. Clearing is what the game leaves after a player clears a node: the record stays with its units
and only "not cleared" goes. Owners are not tied to a Guardian Spirit unit (37 owned nodes have none on the tile), so the editor adds none.
**Real game (slot 6, vault checkpoint 102, Kevin at the keyboard, one End Turn):** a Nature node given to Freya with no spirit on it showed
her aura and stayed hers (memory owner 1); a node made neutral with its guardians restored showed no aura and stayed neutral (owner 0xFF,
guards 3 and 2 intact); the warped flag loaded and survived the turn, and the warped node's tile showed a **distortion animation**.

**Editing units (2026-10-12).** In edit mode the units panel changes the ticked units' **level** (`+12`), **experience** (`+14`), **damage** (`+17`)
and **owner** (`+3`) (`Structures.edit_units/3`, `UnitPanel.changes/1`); an empty field is left alone, and one apply is one undo step. A new owner
clears a go-to order. Refused: an owner change for a hero (he is also in his wizard's hero list), onto a tile with another owner's city, or when
other units stay behind (tick the whole stack). Limits are mine: level 0 to 9, experience 0 to 30000, damage 0 to 255.
**Real game (slot 7, vault checkpoints 103 and 104, Kevin at the keyboard):** Lizardman Spearmen set to level 3 with 0 xp showed "Elite (0 ep)" and
Swordsmen set to level 0 with 200 xp showed "Recruit (200 ep)": **the level byte is shown as it is on load**, not derived. Swordsmen with 4 damage
showed one heart fewer. A melded node's Guardian Spirit given to Freya loaded as hers (blue marker, memory owner 1). **After one End Turn** the
game had recomputed the levels from experience: the Spearmen were level 1 with 7 xp (they gained experience), the Swordsmen level 4 with xp
**capped at 120**, damage healed by 1, the spirit still Freya's. So experience is the lasting field and level alone is overwritten at the next
turn (the panel says so). Not checked: the levels and caps for heroes, who level on a longer table.
**Not done:** editing a unit's type, enchantments, max moves; what the treasure code means (it does not decide the reward) and the item ids.
**Size:** large (do incrementally)

## What to do

A side panel when a structure is selected in edit mode:

- **City**: name, owner, race, population, buildings (later), garrison.
- **Lair / ruin / temple**: type, guardians, treasure, cleared flag.
- **Unit**: type, owner, experience/level, enchantments (later).

Start read-only (it doubles as an inspector in View mode), then make fields
editable one at a time as each byte is verified.

## Definition of done (first slice)

- Selecting a city shows its decoded fields read-only, and name and
  population can be edited and survive a round trip into the real game.
