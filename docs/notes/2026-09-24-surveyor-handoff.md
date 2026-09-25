# 2026-09-24: Surveyor done; where things stand

This supersedes the STORY-034 row of
[2026-09-24-live-ram-evaluation.md](2026-09-24-live-ram-evaluation.md),
which still says "formula no".

## Done

- **STORY-034 Surveyor.** `Mirror.Surveyor.city_resources/5` computes the
  Surveyor's Maximum Pop, Prod Bonus and Gold Bonus, and matches all 15 full
  readouts we have. `panel/6` builds the whole panel, and view mode shows it
  as the `#surveyor` card.
  - The rules and their evidence are in
    [surveyor-formula.md](../reference/surveyor-formula.md).
  - The Python original is in gama (`gama resources`, `gama surveyor --check`).
- **Save decoding.** `Mirror.SaveFile.Cities` now decodes building statuses,
  city enchantments and road links. `Mirror.SaveFile.Sites` decodes the
  positions and kinds of nodes, towers and encounter sites.
- **Wizard record.** Retorts, the spell library (`+0x264`), tax and research
  are checked on screen (wizard-record-and-exploration.md).

## Test data outside the repo

- `~/.mirror/dev/surveyor-fixtures/SAVE9-dior-2026-09-24.GAM`: a frozen copy
  of "Freya - Dior" with edited enchantments. The Surveyor real-file tests
  read it and are skipped without it.
  - Freeze a new copy (`cp`) before building tests on a new game state: the
    game rewrites `SAVE9.GAM` every turn.
- `~/.mirror/dev/save-edits-2026-09-24/`: the original and edited `SAVE5.GAM`
  and the edit script.

## Next candidates

- **STORY-012 units, STORY-011 sites:** both marked ready in the evaluation
  note. `Sites` gives STORY-011 its positions; guard names need the unit
  names.
- **One shared-tile check:** hover an empty tile beside a city and compare
  with `gama resources` or `Mirror.Surveyor`. It's the formula's last
  unchecked rule.
