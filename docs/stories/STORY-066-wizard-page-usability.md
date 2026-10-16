# STORY-066: Wizard page usability: no Apply buttons, feedback, dropdown order

**Parent:** [EPIC-009](../epics/EPIC-009-wizard-editing.md) (wizard editing); the saving part belongs to [EPIC-012](../epics/EPIC-012-open-and-save-from-the-browser.md)
**Status:** decided (2026-10-16), being built
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
- **Feedback sits next to the field:** a small "applied" mark that fades, saying applied, not saved to disk (the header badge says what is unsaved). Nothing waits for the toasts ([STORY-062](STORY-062-fix-the-toasts.md)).
- **A refused value says why, beside the field**, and the field keeps what the user typed. The browser's own form check (`max`, `min`) is not used to block the change, because it blocks silently. **Fame is not limited to 30000**: the game's own save holds 30001; a limit only where the game would break (a number that no longer fits its field: a u16 stops at 65535).
- **Undo and Redo in the header**, next to the Unsaved badge, so a slip on any page is one click to take back. (The history is one for the whole session.)
- **Saving (3)** is done by EPIC-012: nothing to build here.
- **Ordering (4, 5)** as below: items by price, highest first, ties alphabetical, with "(keep what is there)", "(empty)" and "(remove the item)" first; heroes alphabetical by name, the ones already in play stay out of the list.

## Definition of done

- Tests for the two orderings in `WizardPanel` (the pure functions); LiveView tests that a change applies without a button, that an applied change shows its mark and the header's unsaved badge, that a refused value shows its reason and changes nothing, that Fame 30001 is accepted, and that Undo and Redo in the header take a wizard edit back and forward.
- Checked in Chrome: each change visibly answers, and a full edit and save needs no detour through the map page.
