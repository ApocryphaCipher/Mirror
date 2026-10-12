# STORY-047: The wizard page, read-only

**Parent:** [EPIC-009](../epics/EPIC-009-wizard-editing.md)
**Status:** open (2026-10-12), not started
**Size:** medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-12

## What to do

A LiveView at `/wizard/:id` (1 = the player, 2 to 5 the rivals; see the epic for the numbering) that shows what the
save holds for that wizard, using only fields that are already decoded:

- **Header:** name, portrait id (`+0x00`; the portraits are in the game's files, *guess* until checked), banner colour,
  fame, gold, mana, casting skill, power base, tax rate, the summoning circle's plane and position (a link to the
  map, centred on it).
- **Magic:** books per realm (Nature, Sorcery, Chaos, Life, Death), the retorts the wizard has, the research
  ratios, the spell being researched and the research points left.
- **Spells:** the known spells by realm (state 2 in the library).
- **Standing:** how many cities, units and nodes the wizard owns, with links to the map.
- **Background:** a gradient from the wizard's banner colour at the top, fading to black down the screen. Use the
  same banner colours the map's city flags and unit plaques use (blue, green, purple, red, yellow; neutral is
  brown), so the page and the map agree. Check it on a phone-width screen and in dark and light themes.
- Reached from the header (a wizard switcher), and from the map panels' owner names (city, node, unit, lair).

A wizard that does not exist (no name, or an id out of range) is a 404 with a note. **First question:** does
record 5, the neutral player, hold anything worth showing? Read it in a few saves before deciding; if it does, show
it read-only with the brown gradient.

## Definition of done

- Every number on the page matches the game's own screen for the same wizard in a real save (Info, Magic and Research
  screens), checked for the player and for at least one rival.
- LiveView tests on a synthetic save: each section renders, a missing wizard is a 404, the links go to the right place.
- No edit controls yet.
