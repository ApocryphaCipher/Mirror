# STORY-048: Edit a wizard's gold, mana, fame, name, books and retorts

**Parent:** [EPIC-009](../epics/EPIC-009-wizard-editing.md)
**Status:** built and checked in the real game (2026-10-12), PR open; limits still guesses, see Outcome
**Size:** medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-12

## What to do

In edit mode the wizard page gets a form for the fields whose offsets are already checked:

- **Gold** (`+0x356`, u16) and **mana** (`+0x25c`, u16): whole numbers from 0 to **30000**, the game's own cap
  ([uge-mom-model.md](../reference/uge-mom-model.md); in [live-ram-map.md](../reference/live-ram-map.md) a value above it went back to
  30000 by the next screen). 65535 is only the u16 storage range: check what the game does with a value between 30001 and 65535
  in a loaded save before allowing it.
- **Fame** (`+0x24`, u16).
- **Name** (`+0x01`, 20 bytes NUL-padded): printable ASCII only, as for city names (the game's font has no accented
  letters, 2026-10-11); length limit 19 plus the NUL (*check*; city names are 13).
- **Books** (`+0x5a`, 5 × i16): 0 to 13 per realm (*guess* on the top, the game's own limit has to be tested; Kevin's
  Jafar has 12 Sorcery books and the game took it).
- **Retorts** (`+0x64..+0x75`, 18 × u8): tick boxes; the game's rules about which combinations are allowed (a wizard
  with Myrran, Archmage and so on) are not enforced by the save, so the page warns where it knows the rule and does not
  block.

**Derived values stay the game's:** power base (`+0x26`), casting skill and the research candidates are recomputed by the game
(Kevin's Jafar showed "Power Base: 12" until the game was loaded and recomputed it, 2026-10-10). The page shows them and says
so. *Open:* which of them does the game recompute on load and which at End Turn; read it back after each.

One apply is one undo step. Changing the name also changes what every map panel shows for that owner.

## Definition of done

- Each field loads in the real game with the game's screens agreeing (Magic and Info screens), and survives one End Turn; read
  back from memory (`scripts/verify_loaded_save.py`) and a vault checkpoint recorded in this story.
- Unit tests for `Structures.edit_wizard/3` (or the module it lands in) and LiveView tests for the form, refusing bad values
  and saying why.

## Outcome (2026-10-12)

Built: `Structures.edit_wizard/3` (gold, mana, fame, name, books, retorts; refuses with `:bad_gold`, `:bad_mana`, `:bad_fame`,
`:bad_name`, `:bad_books`, `:bad_retorts`, `:no_such_wizard`), `WizardPanel.changes/2`, and an Edit button and form on `/wizard/:id`. One apply is
one undo step on the Arcanus history; Undo and Save as are on the map pages. The neutral record and a nameless record are refused.

**Real game, slot 7** (a SAVE2 copy built with this code; only the 24 intended bytes differed): Jafar renamed "Mirror Test", gold 12345, mana
20000, fame 77, books Nature 0 to 3 (Sorcery 12 kept), Chaos Mastery added; Freya gold 30000, mana 30000, fame 5. Loaded with Load Game:

- The main screen showed 12345 GP and 20000 MP, the Info screen the new name, 15 books and Chaos Mastery in the retort list, the Magic screen
  a reserve of 20000. RAM equals the file except the game's own recomputation: **power base** (952 to 1129) and the order of two research candidates
  (`+0x34`, `+0x36`). Casting skill (217) was unchanged.
- After **one End Turn** everything held: Jafar gold 12345 to 12383 (+38, the main screen's "+38 Gold"), mana 20000 to 19981 (the screen's "-19 Mana"),
  name, books, retorts and fame unchanged; Freya 30000 to 29959 gold and 29984 mana (normal AI spending).
  Vault checkpoint 105, `wizard-edit-after-endturn` (collection mom-live-2026-10-12).
- **Fame:** the Info screen showed **90** while RAM held the 77 we wrote, so the screen is not the raw field; see the maximum test below, where it
  showed 30013 for a stored 30000.

**The maximum test, slot 8** (SAVE2 copy, only wizard 0 changed, 23 bytes): "MAXIMUS", gold, mana and fame 30000, **13 books in every realm (65)**, all 18
retorts. It loaded and ran with no complaint, and survived one End Turn (vault checkpoint 106, `wizard-max-after-endturn`):

- Name, 13 books each and all 18 retorts held. The Info screen draws the 65 books as a shelf running off both edges of its panel, and lists every retort.
- Gold 30000 stayed 30000 after a turn that had +38 gold income (nothing above 30000 was seen), mana 30000 went to 29999 (the screen's "-1 Mana"), fame 30000 stayed.
- The game recomputed power base (1379 at load, 1385 after the turn) and casting skill (217 at load, 222 after).
- **Fame display:** the Info screen showed **30013** for a stored 30000, and 90 for a stored 77 in the first test. Both are the stored value **plus 13**, so it is
  the same bonus in both saves (*guess:* the hero Sir Harold's fame; the same save and hero in both). It is not a limit on the field.

**Limits, now:** books 13 per realm, fame, gold and mana 30000 are all **accepted by the real game** (so they are the form's safe maximum, not a guess).
*Untried:* values above 30000 for fame, gold or mana, and more than 13 books in a realm; the form still refuses them.

**Not done:** warnings for retort combinations. No rule has been checked against the game, so none is shown, and nothing is blocked. (All 18 retorts together, and
both Life and Death books at 13, loaded and ran: the save does not enforce the new-game rules.)
