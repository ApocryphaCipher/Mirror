# STORY-066: Wizard page usability: no Apply buttons, feedback, dropdown order

**Parent:** [EPIC-009](../epics/EPIC-009-wizard-editing.md) (wizard editing); the saving part belongs to [EPIC-012](../epics/EPIC-012-open-and-save-from-the-browser.md)
**Status:** done (2026-10-16), checked by Kevin in Chrome and in the real game
**Size:** small to medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-16, after using the wizard page on Windows with the Steam copy

## What Kevin found

Confirmed working in Mirror and the game (released DOSBox 0.83 on Windows): wizard stats, learned spells, books, retorts, adding heroes, adding magic items to a hero, wizard reputation (relations) and global spells.

Problems on the wizard edit screen:

1. **Apply gives no feedback.** Clicking an Apply button shows nothing. *Found 2026-10-16:* at least one cause is the browser's own form check blocking the submit silently: the wizard form's Fame field has `max` 30000, and a real save (SAVE2) holds 30001, so Apply on that page does nothing at all until the field is changed. The fix belongs here: show the problem, and don't set a limit tighter than what the game's own saves hold.
2. **Several Apply buttons are confusing.** The page has many small forms, each with its own Apply or Set (the wizard form, each hero's form, each item's form and move form, each place's Set, the hero add form).
3. **No Save on the wizard page.** To save: press every Apply, click Done, click Arcanus or Myrror, click Edit, click Save. (Edits are held in the session and only reach a file through Save as on the map page.)
4. **Hero artifact dropdowns** should be ordered by **price, highest first**. Today they are alphabetical (`place_choices/2` in `lib/mirror_web/wizard_panel.ex`).
5. **The hero dropdown** (adding a hero) should be **alphabetical**. Today it is in unit-type number order (`hero_choices/1`).

## Decision (Kevin, 2026-10-16): no Apply buttons

Kevin's question: "Do we even need apply buttons? We have a save component at the top now." No. The slot header (EPIC-012) answers saving and shows the **Unsaved changes** badge, so the Apply buttons only add confusion. This replaces the earlier suggestions (one form with one Apply, or a Set per dropdown).

- **Every field applies by itself.** Dropdowns and checkboxes apply the moment they change. Number and name boxes apply when the user **leaves the box or presses Enter** (not on every keystroke: typing "5000" must not be four edits). No Apply, Set or Add button is left on the page, except where a button is the action itself (adding a hero from its dropdown applies on choosing; there is nothing to "set").
- **Each change is one undo step**, as today (`Editor.apply_record/5`).
- **Feedback:** a message that says what changed ("Edited Jafar: gold 5000"), floating at the bottom right of the screen so it is always in view wherever the page is scrolled, green and fading by itself after about five seconds. (Built bottom right, not beside the field, because the whole form is compared at once: the server knows what changed, not which box.) It says applied, not saved to disk; the header badge says what is unsaved. Nothing waits for the toasts ([STORY-062](STORY-062-fix-the-toasts.md), which may later take this over).
- **A refused value says why** (red, stays until dismissed or the next change), and the box keeps what the user typed. The browser's own form check (`max`, `min`) is switched off on these forms (`novalidate`), because it blocks silently. **Fame at 30001** (the game wrote it) no longer blocks anything: only a *changed* field is checked, so a value already in the save is left alone. Changing a gold, mana or fame to something above 30000 is still refused with a message (the limit was not widened: nothing shows where the game breaks).
- **Undo and Redo in the header**, next to the Unsaved badge, on the wizard pages. They take back and redo the wizard page's own edits (record edits). A map stroke is left for the map, which has to redraw its canvas and tell the engine; the map page keeps its own Undo and Redo.
- **Saving (3)** is done by EPIC-012: nothing to build here.
- **Selects with a placeholder:** "Choose a hero to add…" and "Move to…" are the first choices of those two selects, so that picking any real choice is a change; picking the placeholder does nothing.
- **Ordering (4, 5)** as below: items by price, highest first, ties alphabetical, with "(keep what is there)", "(empty)" and "(remove the item)" first; heroes alphabetical by name, the ones already in play stay out of the list.

## Built (2026-10-16)

`lib/mirror_web/live/wizard_live.ex` (forms listen for changes, no Apply/Set/Add/Move buttons, the floating note, Undo/Redo), `MirrorWeb.SaveSlots.header/1` (the buttons), `lib/mirror_web/wizard_panel.ex` (`place_choices/2` price descending, ties alphabetical; `hero_choices/1` alphabetical), `assets/css/app.css` (the fade). Tests in `wizard_live_test.exs` ("no Apply buttons") and `wizard_panel_test.exs`. Checked in the in-app browser against a real save with a fake folder: typing in Gold and leaving the box applied it with its message and enabled Undo, Undo took it back, a too-big Mana showed its reason and kept the typed value, the Fame 30001 save no longer blocks anything. **Checked by Kevin (Chrome, then the real game, 2026-10-16):** several edits to Jafar in one session (spells, retorts, books, heroes, magic items, relations), saved to slot 8 from the header; the game loaded slot 8 with every change in place and the next turn advanced with no problem.

## Definition of done

- Tests for the two orderings in `WizardPanel` (the pure functions); LiveView tests that a change applies without a button, that an applied change shows its mark and the header's unsaved badge, that a refused value shows its reason and changes nothing, that Fame 30001 is accepted, and that Undo and Redo in the header take a wizard edit back and forward.
- Checked in Chrome: each change visibly answers, and a full edit and save needs no detour through the map page.
