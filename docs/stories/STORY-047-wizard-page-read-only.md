# STORY-047: The wizard page, read-only

**Parent:** [EPIC-009](../epics/EPIC-009-wizard-editing.md)
**Status:** built (2026-10-12), PR open; the "matches the game's own screens" check below is still to do
**Size:** medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-12

## What to do

A LiveView at `/wizard/:id` (1 = the player, 2 to 5 the rivals, 6 the neutral player if it has anything to show; see the epic for the numbering) that shows what the
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
- Reached from the header (a wizard switcher), and from the map panels' owner names (city, node and unit; a lair has no owner, its record is not assigned to a wizard).

A wizard that does not exist (no name, or an id out of range) is a 404 with a note. **First question:** does
record 5, the neutral player (`/wizard/6`), hold anything worth showing? Read it in a few saves before deciding; if it does, show
it read-only with the brown gradient, and if not `/wizard/6` stays a 404.

## Definition of done

- Every number on the page matches the game's own screen for the same wizard in a real save (Info, Magic and Research
  screens), checked for the player and for at least one rival.
- LiveView tests on a synthetic save: each section renders, a missing wizard is a 404, the links go to the right place.
- No edit controls yet.

## Outcome (2026-10-12)

Built: `MirrorWeb.WizardPanel` (pure, `details/2`), `MirrorWeb.WizardLive` at `/wizard/:id`, and links from the owner names in the
city, node and unit panels (neutral stays plain text). The page shows the header numbers, books, retorts, research ratios, the spell being
researched (its number and realm), known spells counted per realm, and the city, unit and node counts, on a gradient from the banner colour to black.
A wizard switcher lists the named wizards. A wizard that does not exist answers HTTP 404 (`MirrorWeb.WizardStatusPlug`) with the note on the page; an owner name links only when that wizard has a name.

- **First question answered:** record 5 (the neutral player) has no name, gold, mana, books or retorts in SAVE1 to SAVE9 (checked
  2026-10-12); only its banner (5) and bytes in the undecoded diplomacy block are set. So `/wizard/6` is a 404, like any nameless record.
- **Review fix:** the researched spell is at `+0x262` and the library at `+0x264` (the first version read both two bytes early); the test now places a single known spell at library byte 0 so a shift shows.
- **Not done yet:** spell *names* (the page shows a number and realm; names need `SPELLDAT.LBX`, not read by Mirror yet), the portrait (id only), the
  summoning-circle link opens the right plane but does not centre the map (the map has no such parameter), and a wizard link in the map page header.
- **Colours:** the page uses fixed CSS hues for the five banners and brown for neutral, close to the map's flags. *Guess* that
  they match closely; the map takes its colours from the game's palette ramps. Compare on screen.
- **Still to do for done:** read the player and one rival against the game's Info, Magic and Research screens; check phone width and the light theme.
  (The in-app browser refused `localhost:4010` this session, so the page has been checked by tests and by reading real saves, not by eye.)
