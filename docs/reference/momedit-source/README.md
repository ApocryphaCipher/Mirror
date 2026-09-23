Source excerpts from **Master Of Magic Game Editor** ("momedit"), a
GPLv2-licensed classic-save editor: https://sourceforge.net/projects/momedit/
(CVS repo, snapshot via `https://sourceforge.net/code-snapshots/cvs/m/mo/momedit.zip`).
Kept as `.txt` (raw RCS `,v` format — CVS stores full revision text inline,
readable as-is) since these are single-revision files with no meaningful
history to preserve.

Used to independently cross-check Mirror's understanding of the classic
`SAVE.GAM` format against a second, real implementation (the first being
the community wiki — see `docs/reference/momedit-source` is unrelated to
`docs/reference/momime-source`, which is the MOMIME Java reimplementation).

| File | What it confirms / reveals |
| --- | --- |
| `Map.cs.txt` | Terrain map offset `0x2698` and layout (u16 per tile, Arcanus block then Myrror block, row-major) — **matches Mirror's implementation exactly.** Cross-validates the offsets Mirror pulled from the community wiki. |
| `MiniMap.cs.txt` | **Terrain classification uses ranges/specific values over the FULL 16-bit raw value** (`value < 0x40` → ocean; tundra includes `0x25a` = 602, which doesn't fit in a byte). Only implements Ocean/Tundra/(buggy)Grassland — not a complete type table — but strong evidence Mirror's byte/nibble-splitting assumption is wrong. See [../../epics/EPIC-003-terrain-value-classification.md](../../epics/EPIC-003-terrain-value-classification.md). |
| `City.cs.txt` | City record layout: base offset `0x8aac`, record length `114` bytes (both match the wiki exactly) with per-field offsets (`+14`=race, `+15`=X, `+16`=Y, `+17`=plane, `+18`=owner, `+20`=population, `+24`=growth rate (int16), `+28`=current production, `+34`=active spells, `+67`=enchantments). See [../../epics/EPIC-004-overland-map-features.md](../../epics/EPIC-004-overland-map-features.md). |

momedit is Alpha-status and doesn't implement a full terrain type enum or
encounter-zone (towers/lairs/ruins) parsing at all — checked `Enums.cs` and
the whole `GameObjects/` folder, nothing there. Don't expect more from this
source than what's excerpted above.
