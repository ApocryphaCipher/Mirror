# Wizard record, second half: heroes, vault, diplomacy, global enchantments; and the item block

Found 2026-10-12 while asking where the game keeps its artifact database (Kevin: the DOS game ships a separate
artifact-maker, `ITEMMAKE.EXE`). Feeds EPIC-009 (wizard page), EPIC-010 (heroes) and EPIC-011 (artifacts).

**Sources:**
- kazzmir's Go remake, [`game/magic/load/load.go`](https://github.com/kazzmir/master-of-magic/blob/master/game/magic/load/load.go)
  (`loadPlayerData`, `loadPlayerHeroData`, `loadDiplomacy`, `loadItems`, read order and field sizes). Offsets below are the
  running sum of his read sizes, which is how the first half of the record was placed and **checked** (research points at
  `+0x25a`, gold at `+0x356` agree with it).
- Kevin's played game (`SAVE2.GAM`), read 2026-10-12: every layout below produced sensible values (the checks are named per row).
- The game's own files in `~/DOS/MAGIC` (not committed): `ITEMDATA.LBX`, `ITEMPOW.LBX`, `ITEMS.LBX`, `ITEMISC.LBX`, `HERODATA.LBX`,
  `ITEMMAKE.EXE`, and the shipped manual of the old DOS editor, `MMOMS.TXT` (MoM Multiplayer Shell), whose editor screens
  (`MAPEDIT7.COM`) show what the community could edit in 1995.

Offsets are from the start of a wizard record, `0x9e8 + n × 0x4c8`; continues
[wizard-record-and-exploration.md](wizard-record-and-exploration.md).

## In the wizard record

| Offset | Field | Checked |
| --- | --- | --- |
| `+0x76` | **hero list**: 6 entries of 28 bytes: unit index (i16, −1 none), name (14 bytes, NUL-padded, the hero's own given name), 3 item indexes (i16, −1 none) into the item block below, 3 item slot types (i16) | **SAVE2:** Jafar's entry 0 is unit 51 "Sir Harold", and unit 51 is a Sir Harold at his capital; Freya's is unit 137 "Rockfist"; the item index 1 is a sword; slot types (1, 5, 6) |
| *(file start)* `6 x 420` | **per-player hero table**, outside the wizard record: 35 heroes x 12 bytes for each of the six players, indexed by unit type 0 to 34: i16 (-20 = hired by that player, *meaning unknown*), 4 ability bytes (*not decoded*), casting skill, 4 spell numbers, 1 pad | **SAVE2, 2026-10-15:** Sir Harold (type 31) and Rockfist (type 6) carry -20 in their own player's table; heroes with spells hold numbers in their realm's range. Read by `Mirror.SaveFile.Heroes` |
| `+0x11e` | 2 unknown bytes | kazzmir |
| `+0x120` | **vault**: 4 item indexes (i16, −1 empty): the wizard's spare items | **SAVE2:** Jafar's vault holds item 2, "Protection of Ramses"; the others have none |
| `+0x128` | **diplomacy**, 306 bytes, six entries per array (players 0 to 4 and 5 = neutral); layout below | **SAVE2:** see below |
| `+0x25a` | research points left (u16) | already checked |
| `+0x356` | gold (u16) | already checked: 8293 on the map screen = the record |
| `+0x358` | unknown (u16) | kazzmir |
| `+0x35a` | astrology: magic power, spell research, army strength (3 × i16, the Astrology screen's three bars) | kazzmir; *guess:* values not read |
| `+0x360` | population (u16) | **SAVE2:** 4, 0, 0, 0, 1 for the five wizards: fits a count the game keeps, *meaning unchecked* |
| `+0x362` | "historian" series, 288 bytes (the Historian screen's graph) | kazzmir |
| `+0x482` | **global enchantments: 24 bytes**, one per global spell, **1 when active**, in the record of the caster | **checked in the real game 2026-10-12** ([findings below](#findings-2026-10-12-aura-of-majesty-just-cause-gold-a-pact-and-threats)): casting Aura of Majesty set byte 3 and Just Cause byte 18, each to 1, and nothing else; the order is `MMOMS.TXT` appendix A.3 (which spells index 3 "Aura of Mastery"; it is Aura of Majesty). The other 22 are the same order, *not yet seen set* |
| `+0x49a` | magic strategy (u16), unknown (u16), then 6 × u16 "hostility" | kazzmir; *guess:* AI hostility toward each player; SAVE2 values are small (Jafar's are 0,0,0,0,2,3) |

### Diplomacy block (306 bytes at `+0x128`), field offsets inside it

Each entry is by *other player* 0 to 5 (the record owner's own slot is 0 or unused).

| In block | Field | Size |
| --- | --- | --- |
| `+0` | contacted | 6 × i8 |
| `+6` | treaty interest, `+18` peace interest, `+30` trade interest | 6 × i16 each |
| `+42` | **visible relations** (the figure the Diplomacy screen shows) | 6 × i8 |
| `+48` | **diplomacy status**, all four **checked in the real game**: **0 none** (peace is just this: a peace treaty with a wizard at war sets 3 back to 0), **1 wizard pact**, **2 alliance**, **3 war**; 4 final war is ReMoM's name, never seen | 6 × i8 |
| `+54` | *guess:* a running count of threats (went to −1 and −4 after threatening Tauron and Sharee; was named "strength" in kazzmir) | 6 × i16 |
| `+66` | action, `+72` spell (i16 × 6), `+84` city | |
| `+90` | **default relations** | 6 × i8 |
| `+96` | contact progress, `+102` broken treaty | 6 × i8 |
| `+108` | unknown | 6 × i16 |
| `+120` | **hidden relations** | 6 × i8 |
| `+126` | unknown (24), `+150` tribute spell (6 × i8), `+156` unknown (90), `+246` tribute gold (6 × i16), `+258` unknown (30), `+288` unknown (6), **`+294` per-wizard flags set to 1 by a threat** (byte `294 + the wizard's number`), `+300` warning progress (6 × i8) | |

**SAVE2:** the values are small signed numbers in the range seen in the game (relations from −81 to +15), the contact flags
match who has met whom, and the status byte is 2 for Freya toward Sharee and Tauron (and Sharee's and Tauron's toward Freya), and 3 for Jafar and for
Tauron toward the neutral side (war with the raiders is the natural reading). That fits the names above, but **no status has been changed in the game
yet**, so the code's meaning is a *guess*.

### Findings, 2026-10-12: Aura of Majesty, Just Cause, gold, a pact and threats

STORY-050 and STORY-051. Test save: the advanced SAVE2 with Jafar given Subversion and Just Cause (slot 7); RAM read with
`scripts/live_session.sh` and a snapshot script that diffs every wizard's diplomacy block and globals between steps. Vault checkpoint
108 (`diplomacy-globals-test`, collection `mom-live-2026-10-12`). Relations below are the visible figures (`+42`), in i8, as the
Diplomacy screen shows them. Kevin's pointer: **a spell is cast at End Turn**, not when it is chosen.

| Step | What changed |
| --- | --- |
| Cast **Aura of Majesty** (400 mana; End Turn) | global byte **3** 0 to 1; visible relations with every wizard in contact set to **20** (Freya 0, Sharee and Tauron -20 before); Sss'ra, not in contact, unchanged; the three interest values rose (treaty 100 to 120..140, peace 100 to 110..120, trade 100 to 120..140); mana fell 140, not 400 (*guess:* the cost is paid over turns) |
| Cast **Just Cause** (End Turn) | global byte **18** 0 to 1; relations 20 to **22** (*the second turn of Aura of Majesty: +2 a turn*); fame stayed at its cap, so the +10 was not seen |
| **50 gold to Freya** | gold moves 1:1; relation 22 to **25** on both sides; nothing else changed |
| **50 gold to Sharee** | relation 22 to **26** (+4 for the same gift) |
| **100 gold to Tauron** | relation 22 to **28** (+6). *Guess:* about the gift ÷ 16, with some variation |
| **Alliance** proposed to Freya, **declined** | nothing changed anywhere |
| **Wizard pact** with Freya, **accepted** | status byte for the other wizard **0 to 1 on both records** (Jafar's `+49`, Freya's `+48`); Jafar's interest values toward Freya fell (treaty 120 to 67, peace 101 to 91, trade 122 to 112); the visible relation did not move |
| **Threat** to Tauron | relation 28 to **23** (-5) on both sides; Jafar's interest values toward Tauron fell (treaty to -220, peace to 1, trade to 42); `+54` entry -1; flag byte `+298` 0 to 1; Tauron's record changed only in the relation |
| **Threat** to Sharee (screen: "Do not make such threats idly, Jafar. The wrath of Sharee is terrible to behold.") | relation 26 to **18** (-8); interest values toward Sharee to -220, -99, -58; `+54` entry -4; flag byte `+297` 0 to 1 |

Peace was greyed out with Freya (no war), and declaring war was refused until relations were bad enough, so **status 3 (war) is still
unproven by a change**. Tauron's next answers were curt ("you have tried my patience") after the threat; the screen text gives the
reaction, the bytes only the relation.

The saved SAVE2 already shows the same codes (Freya toward Sharee 2, toward Tauron 1, now seen with 1 = pact checked), so 2 as an alliance is
the natural reading, *guess* until one is made.

### Findings, 2026-10-13: writing relations and statuses by hand (STORY-050)

Test save (slot 7): the advanced SAVE2 with, written by `Structures.edit_wizard/3` on both wizards' records: Jafar and Freya relation 70; Jafar and
Sharee +50 with status 2; Jafar and Tauron -90 with status 3. Ten bytes differed. Vault checkpoint 109 (`relations-edit-test`).

- **The game takes them as written:** RAM equals the file on load. The Magic screen's icons by each portrait match: **crossed swords** for 3 (blue, by Tauron),
  a **round peace symbol** for 2 (blue by Sharee for Jafar, green by Sharee for Freya), a **rectangle** for 1 (the Freya-Tauron pact). The icon's colour is the
  other wizard's banner. The attitude words by the portraits: 70 "Peaceful", +50 "Calm", 0 "Neutral", -20 "Uneasy", -90 "Hate".
- **The Diplomacy menu follows the status:** at 3 (war) *Peace Treaty* is offered and Wizard Pact, Alliance and the other proposals are greyed; at 2 (alliance) Wizard Pact,
  Alliance and Peace Treaty are greyed and *Break Alliance With Another Wizard* and *Declaration of War on Another Wizard* are offered; at 0, *Threaten/Break Treaty*
  and *Exchange Spells* are available (they are greyed at war). Tauron still greeted Jafar politely at -90.
- **Peace:** Tauron **accepted a peace treaty at relation -90**; status 3 became **0** on both records and the relation rose to -50 (+40), with the interest
  values toward him spent (treaty 100 to 34, peace 101 to 71, trade 104 to 74).
- **One End Turn:** the alliance and the relations were kept; allies and pact partners drifted up a few points (Jafar-Sharee 50 to 52, Freya-Sharee 14 to 18, Freya-Tauron 18 to 20);
  a relation with no treaty (Jafar-Freya 70) did not move.

### Finding, 2026-10-13: the banished flag (STORY-050)

Kevin: "there is probably a defeated status" (it turned out to be *banished*, below). `JAFAR-PLAYED.GAM` has a wizard (Freya) with no cities, no units, no heroes (slots 255), 0 gold, still named, and **fortress record 1 = (23, 25, Arcanus, active 0)**,
where every living wizard's active byte is 1. Loaded in the game (slot 6), her Magic-screen portrait is a **cracked stone frame** with no attitude label (an unmet wizard is a plain grey gem).
Two one-byte tests, `0x65FF` (the fourth byte of record 1): set to 1 on the dead save and her frame is a plain gem again, set to 0 on a living Freya (the advanced SAVE2, two cities) and the frame is cracked.
So the game decides "banished" from the **fortress active byte** (`0x65F8 + 4 × wizard + 3`), not from the city count. The conqueror's `+0x354` (a u16 between the spell library and the gold, kazzmir's `DefeatedWizards`) is 2 in that save and 0 in the others
(*guess:* a count of wizards he has defeated). **Banished is not dead.** The 1995 editor's manual (`MMOMS.TXT` section 5.3, "Losing Your Fortress") says a wizard who loses his fortress "will automatically begin casting Spell of Return, whether you had any cities left or not", and is only resigned if he has no cities the following turn. That fits both observations: a living Freya with two cities was cracked by the one byte (banished), and the Freya in `JAFAR-PLAYED` had it cleared and nothing left (banished and eliminated). Spell of Return is spell 214 in `SPELLDAT.LBX` (Arcane). The page and the docs say **banished**.
*Not seen:* what a turn does to a wizard whose flag was cleared by hand, or what the Diplomacy screen offers for a defeated wizard.

## The item block: `0x6fb8`, 138 × 50 bytes

Right after the encounters (`0x6628 + 102 × 24`) and right before the cities (`0x8aac`), so the sum checks: `0x6fb8 + 138 × 50 = 0x8aac`.
Item indexes in the save (a hero's three, the vault's four) are positions in this array. **A lair's `+18..+22` are not** (2026-10-15, STORY-054): in 22 saves they hold 360, 520, 1200 and so on, up to 2400, never a value in 1 to 137, and there is one per counted item. *Guess:* the value the item rolled when the lair is cleared may be worth. The lair's reward is made at clearing (see STORY-020), so the lair never holds an item record before that.

| In record | Field |
| --- | --- |
| `+0` | name (30 bytes, NUL-padded) |
| `+30` | icon (u16, an entry of `ITEMS.LBX`) |
| `+32` | slot, `+33` type (kazzmir's names; the codes are not mapped) |
| `+34` | cost (u16) |
| `+36..+43` | attack, to hit, defense, movement, resistance, spell skill, spell save, spell (8 × u8) |
| `+44` | charges (u16) |
| `+46` | abilities (u32 bit mask) |

**Free slot** (2026-10-15): a record with an empty name; `Mirror.SaveFile.Items` skips it (SAVE2 has one such record, index 13, with leftover bytes in it). **SAVE2:** index 1 is "Mae Govannon" (cost 1200, +1 to hit) and index 2 "Protection of Ramses" (cost 2100, +6 defense, +8 resistance,
a sword and a shield by name), the two items the heroes and the vault point at. A save always has 138 slots; how a slot is marked
free is not yet read.

## The game's own artifact data

`ITEMMAKE.EXE` is the Create Artifact screen, a separate program the game runs. It reads:
- **`ITEMDATA.LBX`**: one entry, 250 records of 56 bytes: the 250 **premade items**. A record is the save's item record
  (above) with a 6-byte tail: name (30), icon, slot, type, cost, the eight stat bytes, charges, abilities, then 6 bytes not
  read. The save has a 250-byte table of "premade items still available" right after the heroes block (kazzmir
  `loadPremadeItems`, *guess:* 0 or 1 each).
- **Which copy of `ITEMDATA.LBX`:** ITEMMAKE.EXE **saves its edits straight back to `ITEMDATA.LBX`** (2026-10-12: Kevin browsing
  it changed the file in `~/DOS/MAGIC`; there is no way to leave the program without saving). The 2026-10-12 checks used a
  file that differed from the original GOG copy in 3 records (items 1, 51 and 75; item 75 had its type changed from shield to misc and
  its tail bytes moved with it, which shows the tail depends on the type). None of the 14 checked items is one of the three. The
  community patch's copy and the old CD install's copy differ from the GOG original in about 25 records or more (the patch rebalances
  items), so "the premade items" depends on which game files a save was made with.
- **`ITEMPOW.LBX`**: one entry, 67 records of 30 bytes: the **item powers** ("+1 Attack" to "Spell Charges"). A record is a name
  (22 bytes), then a kind (u8), a realm (u8), an amount (u8), a pad, and a **u32 ability mask**. The item's abilities are the OR of
  its powers' masks. **Read by `Mirror.ItemPowers`** (2026-10-15; 66 named powers, the 67th record is empty): the stat powers have a zero mask (they are the item's stat bytes), the special powers one bit each. On SAVE2 the mask of "Plate of Enduring Immunity" (`0x82000`) comes out as Magic Immunity and Endurance, Mae Govannon's (`0x4`) as Lightning, Protection of Ramses' (`0x2008`) as Cloak of Fear and Endurance.

**Checked against `ITEMMAKE.EXE` itself (Kevin ran it, 2026-10-12, 14 screenshots, item numbers 1, 15, 25, 31, 37, 45, 50, 53, 58, 62,
65, 76, 85 and 95):** the program's "Item #n" is `ITEMDATA` record n − 1, and for **every one of the 14** the program's name,
tab, cost, ticked stat powers and ticked special powers equal the record's name, type, cost, stat bytes and ability mask (the mask
is the OR of the ticked powers' masks in `ITEMPOW`). So the program is an editor for the premade table (*guess:* it saves back to
`ITEMDATA.LBX`), the item records above are right, and:

- **Type codes** are the program's ten tabs in order: **0 Sword, 1 Mace, 2 Axe, 3 Bow, 4 Staff, 5 Wand, 6 Misc, 7 Shield, 8 Chain,
  9 Plate** (seen: 0, 1, 2, 3, 4, 5, 6, 7, 8 and 9 each on at least one item).
- **Slot codes** (what a hero's slot type must equal, except that **3** accepts any weapon kind; the heroes' own three slot types are in the hero list; see `Mirror.SaveFile.HeroTypes` for each hero's three): **1** melee weapon (sword,
  mace, axe), **2** bow, **4** staff and wand, **5** armor and shield (shield, chain, plate), **6** misc (amulets and the like). Seen
  on all 14 items.
- **Stat bytes** are the plain numbers on the screen: attack, to hit, defense, movement, resistance, spell skill, and spell save (the
  save byte `1` is the screen's "−1 Spell Save").
- **A charged spell** is the `spell` byte plus `charges`: "Mind Storm x4" is spell byte 67 and charges 4. The spell number is
  **1-based**: the manual's list numbers Mind Storm 066.
- The power's **realm byte** is 0 Nature, 1 Sorcery, 2 Chaos, 3 Life, 4 Death, which matches every named spell power (Resist Elements
  is 0, Haste 1, Flaming 2, Holy Avenger 3, Vampiric 4).
- **The 6-byte tail of a premade record** (*unknown*): its last byte is 1 for every item but the plain amulet, and the other
  bytes hold small numbers equal to the amounts of the item's powers (3 for a +3 power, 6 for a 6, 2 for a 2) in positions that
  do not follow the realm order cleanly, so they look like per-realm book requirements; not decoded.

- **`ITEMS.LBX`** (116 pictures) and **`ITEMISC.LBX`** (36): the item art.

The 250 premade names and the 67 powers are game data and stay out of the repository; the decoder will read them from
`MIRROR_MOM_PATH`.

## What the old DOS editor's screens tell us

`MMOMS.TXT` ships with the game folder (the community "MoM Multiplayer Shell" editor; `MAPEDIT7.COM` is its editor).
Its editor screens show what its author found editable in 1995, which is a map for ours:
- **Wizard:** gold, mana, fame, skill, race, the five book counts, the retorts ("skills"), every spell as *not known /
  known / unchangeable (in the research book) / researchable*, and **"globals" yes/no**: so the global enchantments are plain
  per-wizard flags, as above. Spells are numbered 0 to 239 in the realm order Nature, Sorcery, Chaos, Life, Death, Arcane
  (40 each; Arcane uses 200 to 213); the 24 globals are numbered 0 to 23. The manual lists both (appendix A.2 and A.3).
- **Lair, tower or node:** two guard units (type and number), and a treasure screen with **gold, mana, prisoner (yes/no), "magic"
  (none, common spell, uncommon spell, rare spell, very rare spell, 1 retort or spellbook pick, 2 retort or spellbook picks),
  the number of magic items, and an "item chance, out of 16"**. That is seven values for the seven treasure codes (0 to 6) in the
  lair record's `+14`, which was our open question in STORY-020. It is a *lead, not a decode*: our own experiments (2026-10-12) did
  not match it cleanly (code 5 gave a Chain Mail and a Disjunction spell, not a retort or a book), so it needs a retest. The
  "prisoner" and "item chance" fields would be the two bytes still unknown in the record (`+9` and `+17`, which are 0 in every one
  of 1,713 lair records here).
- **City:** owner, race, population. **Units:** edit units in a city. **Structures:** select and move (we did these too).
- There is **no diplomacy editor** in it: relations and treaties are new ground.
