# EPIC-009: Wizard editing: a page per wizard

**Status:** in progress (2026-10-12): STORY-047 and 048 built, the rest not started
**Owner:** [Kevin](https://github.com/KevinAsbury)
**Requested:** 2026-10-12. Kevin: a `/wizard/:id` page that shows a wizard's information and lets you edit
gold, mana, fame and special abilities (retorts); a relationship editor; the global enchantments, with the
ability to add and remove them; what the wizard is researching; books; the name; peace/war tags; and a
gradient background of the wizard's flag colour at the top, fading to black down the page.

## The idea

The map pages edit the *world* (terrain, structures, units). A wizard is the other half of the save: the
player and the AI rivals each have a record of power, spells, research and standing. EPIC-006's panels already
show a wizard's name where they need one (a city's owner, a node's melder); this epic gives each wizard a page
of their own, reached from those names and from the header.

## Addresses

`/wizard/1` is the player, `/wizard/2` to `/wizard/5` are the AI wizards in a full game, and **`/wizard/6` is reserved for the neutral
player** (the save's record 5), which is a 404: STORY-047 looked (2026-10-12, SAVE1 to SAVE9) and found no name, gold, mana or books, only the banner and undecoded diplomacy bytes. The
number is the **save's wizard record plus one** (record 0 is the player, which is what the rest of Mirror calls
"wizard 0"; the page uses the human numbering). A small world has fewer wizards: a record with no name is "no such
wizard" (404). The save holds a **sixth record, number 5, for the neutral player** (the brown banner: neutral cities,
nodes' guardians and lairs), reached at `/wizard/6`; whether it carries anything worth showing is STORY-047's first question, and it is
read-only if it does.

The page reads the **current session's save**, like the map pages, and in edit mode changes it as one undo step
per apply (`Editor.apply_record/5`), with Save as writing the bytes. The same safety rules hold (AGENTS.md section 9).

## What is already decoded, and what is not

Decoded and checked against the game's own screens
([wizard-record-and-exploration.md](../reference/wizard-record-and-exploration.md)): name (`+0x01`), banner
(`+0x16`), fame (`+0x24`), power base (`+0x26`, derived by the game), research/mana/skill ratios (`+0x2a..`),
summoning circle, casting skill (`+0x54`, `+0x56`), tax rate (`+0x58`), books per realm (`+0x5a`), the 18 retorts
(`+0x64..+0x75`), research points left (`+0x25a`), mana (`+0x25c`), the spell being researched (`+0x262`), the
spell library (`+0x264`, 240 states: 214 used) and gold (`+0x356`).

**Located, not yet changed in the game (2026-10-12):** relations between wizards (a 306-byte diplomacy block at `+0x128`) and the
global enchantments (24 bytes at `+0x482`, one per global spell, in the wizard record of whoever cast it). Found from kazzmir's
loader (`game/magic/load/load.go`, the source the wizard table already comes from) and read in Kevin's played save, where the
values are sensible; see [wizard-heroes-diplomacy-items.md](../reference/wizard-heroes-diplomacy-items.md). What each code means
(the status byte, a global's non-zero value) is still a guess until one is changed in the real game
([real-game-acceptance.md](../reference/real-game-acceptance.md)). The game folder also holds the 1995 DOS editor's manual
(`MMOMS.TXT`), whose wizard screen already edits gold, mana, fame, books, retorts, spells and the globals. Heroes and artifacts are
[EPIC-010](EPIC-010-heroes.md) and [EPIC-011](EPIC-011-artifacts.md).

## Stories

- [STORY-047](../stories/STORY-047-wizard-page-read-only.md): the `/wizard/:id` page, read-only, with the flag-colour gradient and links from the map panels
- [STORY-048](../stories/STORY-048-wizard-basics-editing.md): edit gold, mana, fame, name, books and retorts
- [STORY-049](../stories/STORY-049-wizard-spells-and-research.md): the spell library and what is being researched
- [STORY-050](../stories/STORY-050-wizard-relations.md): relations between wizards: peace, war, attitude (decode, then edit)
- [STORY-051](../stories/STORY-051-global-enchantments.md): global enchantments: see, add, remove (decode, then edit)

Heroes and artifacts are their own epics, [EPIC-010](EPIC-010-heroes.md) and [EPIC-011](EPIC-011-artifacts.md); the wizard
page shows their results once they exist.

Suggested order: 047, 048, 049, then 050 and 051 (each starts with a decode).
