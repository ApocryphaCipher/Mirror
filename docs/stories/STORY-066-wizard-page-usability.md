# STORY-066: Wizard page usability: feedback, one Apply, saving, dropdown order

**Parent:** [EPIC-009](../epics/EPIC-009-wizard-editing.md) (wizard editing); the saving part belongs to [EPIC-012](../epics/EPIC-012-open-and-save-from-the-browser.md)
**Status:** open (2026-10-16)
**Size:** small to medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-16, after using the wizard page on Windows with the Steam copy

## What Kevin found

Confirmed working in Mirror and the game (released DOSBox 0.83 on Windows): wizard stats, learned spells, books, retorts, adding heroes, adding magic items to a hero, wizard reputation (relations) and global spells.

Problems on the wizard edit screen:

1. **Apply gives no feedback.** Clicking an Apply button shows nothing.
2. **Several Apply buttons are confusing.** The page has many small forms, each with its own Apply or Set (the wizard form, each hero's form, each item's form and move form, each place's Set, the hero add form).
3. **No Save on the wizard page.** To save: press every Apply, click Done, click Arcanus or Myrror, click Edit, click Save. (Edits are held in the session and only reach a file through Save as on the map page.)
4. **Hero artifact dropdowns** should be ordered by **price, highest first**. Today they are alphabetical (`place_choices/2` in `lib/mirror_web/wizard_panel.ex`).
5. **The hero dropdown** (adding a hero) should be **alphabetical**. Today it is in unit-type number order (`hero_choices/1`).

## Suggestions (Kevin to decide)

- **Feedback (1):** after each apply, a short confirmation that names what changed ("Gold set to 1234", "Sir Harold's level set to 3") as a toast ([STORY-062](STORY-062-fix-the-toasts.md)), and a brief highlight on the changed field. A refused edit says why, in the same place. Until the toasts are fixed, an inline line next to the button works.
- **Fewer Apply buttons (2):** *suggestion:* the wizard's own numbers, books, retorts, spells, relations and global enchantments become **one form with one Apply** (they are one record; today the sections already feed one change). Heroes and items stay per-item, but a change in a dropdown applies at once (no separate Set) and says so. *Alternative:* every field applies the moment it changes. Each apply stays one undo step either way.
- **Saving (3):** the cleanest fix is [STORY-058](STORY-058-top-bar-and-unsaved-badge.md) (a page-wide top bar with Save and an "unsaved changes" badge) and the slot buttons of STORY-059 and 060. If that is far off, a cheap interim is a Save as button on the wizard page itself. *Recommendation:* do STORY-058 first, since it fixes this on every page.
- **Ordering (4, 5):** items: price descending, ties alphabetical, and keep "(keep what is there)", "(empty)" and "(remove the item)" first. Heroes: alphabetical by name; the ones already in play stay out of the list as now.

## Definition of done

- Tests for the two orderings in `WizardPanel` (the pure functions), and a LiveView test that an apply shows its confirmation.
- Checked in Chrome: each apply visibly answers, and a full edit-and-save needs no detour through the map page.
