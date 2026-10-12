# STORY-020: Structure detail editors (city / lair / unit)

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** later (2026-10-07). The records for the first slice are decoded for reading (cities:
name, owner, race, population; units: type, owner; sites: kind, guards, rewards, see
[kazzmir-save-layouts.md](../reference/kazzmir-save-layouts.md)); what it needs next is each
editable field checked in the real game, one at a time.
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

**Not done:** lairs and units (the other panels in this story).
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
